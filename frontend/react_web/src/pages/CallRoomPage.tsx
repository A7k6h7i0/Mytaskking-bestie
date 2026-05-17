import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import AgoraRTC, { IAgoraRTCClient, ICameraVideoTrack, IMicrophoneAudioTrack, IRemoteAudioTrack, IAgoraRTCRemoteUser } from 'agora-rtc-sdk-ng';
import { Camera, CameraOff, Mic, MicOff, PhoneOff, Radio, ShieldCheck, Users, Volume2 } from 'lucide-react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { toast } from '@/components/Toast';
import { useAuthStore } from '@/store/auth';
import { useCallStore } from '@/store/calls';
import './call-room.css';

type CallToken = {
  token: string;
  channelName: string;
  uid: string;
  expiresAt: number;
  appId: string;
  room?: { id: string; slug?: string; name?: string };
};

type HistoryCall = {
  id: string;
  kind: 'ONE_TO_ONE' | 'GROUP';
  status: string;
  createdAt: string;
  initiator?: { id: string; name: string; avatarUrl?: string | null };
  participants: Array<{ userId: string; joinedAt?: string | null; leftAt?: string | null; muted?: boolean; user: { id: string; name: string; avatarUrl?: string | null; role: string; isClient: boolean } }>;
};

const rtcClient = AgoraRTC.createClient({ mode: 'rtc', codec: 'vp8' });

export default function CallRoomPage() {
  const { callId = '' } = useParams();
  const navigate = useNavigate();
  const me = useAuthStore((s) => s.user)!;
  const pending = useCallStore((s) => s.pending);
  const clearPending = useCallStore((s) => s.clearPending);
  const setCurrentCall = useCallStore((s) => s.setCurrentCall);
  const [joined, setJoined] = useState(false);
  const [muted, setMuted] = useState(false);
  const [cameraOn, setCameraOn] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [remoteUsers, setRemoteUsers] = useState<IAgoraRTCRemoteUser[]>([]);
  const clientRef = useRef<IAgoraRTCClient | null>(null);
  const micTrackRef = useRef<IMicrophoneAudioTrack | null>(null);
  const cameraTrackRef = useRef<ICameraVideoTrack | null>(null);
  const localVideoRef = useRef<HTMLDivElement | null>(null);
  const remoteVideoRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const ringtoneRef = useRef<{ stop: () => void } | null>(null);

  const { data: history } = useQuery<{ items: HistoryCall[] }>({
    queryKey: ['calls.history.live'],
    queryFn: async () => (await api.get('/calls/history')).data,
    refetchInterval: joined ? 10000 : false,
  });

  const activeCall = useMemo(() => (history?.items || []).find((item) => item.id === callId) || pending?.call || null, [history?.items, callId, pending?.call]);

  const tokenQuery = useQuery<CallToken>({
    queryKey: ['calls.token', callId],
    queryFn: async () => (await api.get(`/calls/${callId}/token`)).data,
    enabled: !!callId,
    retry: 1,
  });

  const joinMut = useMutation({
    mutationFn: async () => {
      await api.post(`/calls/${callId}/join`);
      return tokenQuery.refetch();
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not join call'),
  });

  async function connect() {
    if (joined || connecting) return;
    const token = tokenQuery.data;
    if (!token?.appId || !token?.token || !token?.channelName) {
      toast.error('Call token is not ready yet');
      return;
    }

    setConnecting(true);
    try {
      const client = rtcClient;
      clientRef.current = client;

      const syncUsers = () => setRemoteUsers([...client.remoteUsers]);
      client.removeAllListeners();
      client.on('user-published', async (user, mediaType) => {
        await client.subscribe(user, mediaType);
        if (mediaType === 'audio') {
          (user.audioTrack as IRemoteAudioTrack | undefined)?.play();
        }
        if (mediaType === 'video') {
          const el = remoteVideoRefs.current[String(user.uid)];
          if (el) user.videoTrack?.play(el);
        }
        syncUsers();
      });
      client.on('user-unpublished', (user, mediaType) => {
        if (mediaType === 'audio') {
          (user.audioTrack as IRemoteAudioTrack | undefined)?.stop();
        }
        if (mediaType === 'video') {
          user.videoTrack?.stop();
        }
        syncUsers();
      });
      client.on('user-joined', syncUsers);
      client.on('user-left', syncUsers);

      await client.join(token.appId, token.channelName, token.token, token.uid);
      const micTrack = await AgoraRTC.createMicrophoneAudioTrack();
      micTrackRef.current = micTrack;
      await client.publish([micTrack]);
      setJoined(true);
      setMuted(false);
      setRemoteUsers([...client.remoteUsers]);
      setCurrentCall(callId);
      clearPending();
      toast.success('Connected to Agora call');
    } catch (err: any) {
      toast.error('Could not join Agora call', err?.message || 'Please try again.');
      await disconnect(true);
    } finally {
      setConnecting(false);
    }
  }

  async function disconnect(silent = false) {
    try {
      if (micTrackRef.current) {
        micTrackRef.current.stop();
        micTrackRef.current.close();
        micTrackRef.current = null;
      }
      if (cameraTrackRef.current) {
        cameraTrackRef.current.stop();
        cameraTrackRef.current.close();
        cameraTrackRef.current = null;
      }
      if (clientRef.current) {
        await clientRef.current.leave();
        clientRef.current.removeAllListeners();
        clientRef.current = null;
      }
    } catch {}
    setRemoteUsers([]);
    setJoined(false);
    setMuted(false);
    setCurrentCall(null);
    if (!silent) {
      await api.post(`/calls/${callId}/leave`).catch(() => {});
      toast.info('Left the call');
    }
  }

  useEffect(() => {
    joinMut.mutate();
    return () => {
      disconnect(true);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [callId]);

  useEffect(() => {
    if (!joined) return;
    ringtoneRef.current?.stop();
    const id = window.setInterval(() => setSeconds((s) => s + 1), 1000);
    return () => window.clearInterval(id);
  }, [joined]);

  useEffect(() => {
    if (pending?.call?.id !== callId || joined) return;
    const AudioCtx = window.AudioContext || (window as any).webkitAudioContext;
    if (!AudioCtx) return;
    const ctx = new AudioCtx();
    let cancelled = false;
    const play = () => {
      if (cancelled) return;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = 880;
      gain.gain.value = 0.03;
      osc.connect(gain).connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.25);
      setTimeout(() => {
        if (cancelled) return;
        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.value = 660;
        gain2.gain.value = 0.025;
        osc2.connect(gain2).connect(ctx.destination);
        osc2.start();
        osc2.stop(ctx.currentTime + 0.22);
      }, 320);
    };
    play();
    const interval = window.setInterval(play, 1800);
    ringtoneRef.current = { stop: () => { cancelled = true; window.clearInterval(interval); ctx.close().catch(() => {}); } };
    return () => ringtoneRef.current?.stop();
  }, [pending?.call?.id, callId, joined]);

  useEffect(() => {
    if (tokenQuery.data && !joined && !connecting) {
      connect();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tokenQuery.data?.token]);

  async function toggleMute() {
    if (!micTrackRef.current) return;
    const next = !muted;
    await micTrackRef.current.setEnabled(!next);
    await api.post(`/calls/${callId}/mute`, { muted: next }).catch(() => {});
    setMuted(next);
  }

  async function toggleCamera() {
    if (!clientRef.current) return;
    if (cameraOn) {
      if (cameraTrackRef.current) {
        await clientRef.current.unpublish([cameraTrackRef.current]);
        cameraTrackRef.current.stop();
        cameraTrackRef.current.close();
        cameraTrackRef.current = null;
      }
      setCameraOn(false);
      return;
    }

    try {
      const cam = await AgoraRTC.createCameraVideoTrack();
      cameraTrackRef.current = cam;
      await clientRef.current.publish([cam]);
      if (localVideoRef.current) cam.play(localVideoRef.current);
      setCameraOn(true);
      toast.success('Camera is live on Agora');
    } catch (err: any) {
      toast.error('Could not start camera', err?.message || 'Check camera permissions.');
    }
  }

  async function hangUp() {
    await disconnect();
    navigate('/calls', { replace: true });
  }

  const otherParticipants = (activeCall?.participants || []).filter((p: any) => p.user?.id !== me.id);
  const timerText = new Date(seconds * 1000).toISOString().slice(14, 19);

  return (
    <div className="cr">
      <header className="cr__head">
        <div>
          <div className="cr__eyebrow"><Radio size={14} /> Powered by Agora</div>
          <h1>{activeCall?.kind === 'GROUP' ? 'Group voice room' : 'Direct voice call'}</h1>
          <p>
            {activeCall?.status ? `Status: ${activeCall.status}` : 'Connecting your secure audio room…'}
            {' · '}
            Low-latency voice session with Agora RTC.
          </p>
        </div>
        <div className="cr__brand-card">
          <ShieldCheck size={18} />
          <span>Agora calling</span>
        </div>
      </header>

      <section className="cr__panel">
        <div className="cr__summary">
          <div className="cr__summary-card">
            <span className="cr__summary-label">Call type</span>
            <strong>{activeCall?.kind === 'GROUP' ? 'Group' : 'One-to-one'}</strong>
          </div>
          <div className="cr__summary-card">
            <span className="cr__summary-label">Connection</span>
            <strong>{joined ? `Live on Agora · ${timerText}` : connecting ? 'Joining…' : 'Waiting'}</strong>
          </div>
          <div className="cr__summary-card">
            <span className="cr__summary-label">Remote listeners</span>
            <strong>{remoteUsers.length}</strong>
          </div>
        </div>

        <div className="cr__video-grid">
          <div className="cr__video-card cr__video-card--local">
            <div className="cr__video-label">You {cameraOn ? '· camera on' : '· audio only'}</div>
            <div ref={localVideoRef} className={`cr__video-surface ${cameraOn ? 'has-video' : ''}`}>
              {!cameraOn && <div className="cr__video-placeholder"><Avatar name={me.name} src={me.avatarUrl} isClient={me.isClient} size={56} /></div>}
            </div>
          </div>
          {otherParticipants.map((p: any) => {
            const remoteUser = remoteUsers.find((u) => String(u.uid) === p.user.id);
            const remoteHasVideo = !!remoteUser?.videoTrack;
            return (
              <div key={`video-${p.user.id}`} className="cr__video-card">
                <div className="cr__video-label">{p.user.name} {remoteHasVideo ? '· video live' : '· audio only'}</div>
                <div ref={(el) => { remoteVideoRefs.current[p.user.id] = el; }} className={`cr__video-surface ${remoteHasVideo ? 'has-video' : ''}`}>
                  {!remoteHasVideo && <div className="cr__video-placeholder"><Avatar name={p.user.name} src={p.user.avatarUrl} isClient={p.user.isClient} size={56} /></div>}
                </div>
              </div>
            );
          })}
        </div>

        <div className="cr__people">
          <div className="cr__people-head"><Users size={16} /> Participants</div>
          <div className="cr__people-list">
            <article className="cr__person cr__person--me">
              <Avatar name={me.name} src={me.avatarUrl} isClient={me.isClient} size={42} />
              <div>
                <UserName name={me.name} isClient={me.isClient} role={me.role} />
                <div className="cr__person-sub">You {muted ? '· muted' : '· microphone on'}</div>
              </div>
            </article>
            {otherParticipants.map((p: any) => {
              const remoteJoined = remoteUsers.some((u) => String(u.uid) === p.user.id);
              return (
                <article key={p.user.id} className="cr__person">
                  <Avatar name={p.user.name} src={p.user.avatarUrl} isClient={p.user.isClient} size={42} />
                  <div>
                    <UserName name={p.user.name} isClient={p.user.isClient} role={p.user.role} />
                    <div className="cr__person-sub">{remoteJoined ? 'Live in Agora room' : 'Waiting to join'}</div>
                  </div>
                  <span className={`cr__presence ${remoteJoined ? 'is-live' : ''}`}>
                    <Volume2 size={14} /> {remoteJoined ? 'Connected' : 'Pending'}
                  </span>
                </article>
              );
            })}
          </div>
        </div>

        <div className="cr__actions">
          <Button variant={muted ? 'secondary' : 'ghost'} onClick={toggleMute} disabled={!joined || connecting}>
            {muted ? <MicOff size={16} /> : <Mic size={16} />} {muted ? 'Unmute' : 'Mute'}
          </Button>
          <Button variant={cameraOn ? 'secondary' : 'ghost'} onClick={toggleCamera} disabled={!joined || connecting}>
            {cameraOn ? <CameraOff size={16} /> : <Camera size={16} />} {cameraOn ? 'Stop video' : 'Start video'}
          </Button>
          <Button variant="danger" onClick={hangUp}>
            <PhoneOff size={16} /> Leave call
          </Button>
        </div>
      </section>
    </div>
  );
}
