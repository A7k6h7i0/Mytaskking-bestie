import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import AgoraRTC, { IAgoraRTCClient, ICameraVideoTrack, ILocalAudioTrack, ILocalVideoTrack, IMicrophoneAudioTrack, IRemoteAudioTrack, IAgoraRTCRemoteUser } from 'agora-rtc-sdk-ng';
import { Camera, CameraOff, Mic, MicOff, MonitorUp, PhoneOff, Radio, ShieldCheck, Users, Volume2, VolumeX } from 'lucide-react';
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
  const [sharingScreen, setSharingScreen] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [remoteUsers, setRemoteUsers] = useState<IAgoraRTCRemoteUser[]>([]);
  const [microphones, setMicrophones] = useState<MediaDeviceInfo[]>([]);
  const [cameras, setCameras] = useState<MediaDeviceInfo[]>([]);
  const [speakers, setSpeakers] = useState<MediaDeviceInfo[]>([]);
  const [selectedMicId, setSelectedMicId] = useState('');
  const [selectedCameraId, setSelectedCameraId] = useState('');
  const [selectedSpeakerId, setSelectedSpeakerId] = useState('');
  const clientRef = useRef<IAgoraRTCClient | null>(null);
  const micTrackRef = useRef<IMicrophoneAudioTrack | null>(null);
  const cameraTrackRef = useRef<ICameraVideoTrack | null>(null);
  const localVideoTrackRef = useRef<ILocalVideoTrack | null>(null);
  const screenAudioTrackRef = useRef<ILocalAudioTrack | null>(null);
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
          const audioTrack = user.audioTrack as IRemoteAudioTrack | undefined;
          audioTrack?.play();
          if (selectedSpeakerId && audioTrack?.setPlaybackDevice) {
            try {
              await audioTrack.setPlaybackDevice(selectedSpeakerId);
            } catch {}
          }
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
      const [micList, cameraList, speakerList] = await Promise.all([
        AgoraRTC.getMicrophones().catch(() => []),
        AgoraRTC.getCameras().catch(() => []),
        AgoraRTC.getPlaybackDevices().catch(() => []),
      ]);
      setMicrophones(micList);
      setCameras(cameraList);
      setSpeakers(speakerList);
      setSelectedMicId(micTrack.getTrackLabel() ? micTrack.getMediaStreamTrack().getSettings().deviceId || micList[0]?.deviceId || '' : micList[0]?.deviceId || '');
      setSelectedCameraId(cameraList[0]?.deviceId || '');
      setSelectedSpeakerId(speakerList[0]?.deviceId || '');
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
      if (localVideoTrackRef.current) {
        localVideoTrackRef.current.stop();
        localVideoTrackRef.current.close();
        localVideoTrackRef.current = null;
      }
      if (screenAudioTrackRef.current) {
        screenAudioTrackRef.current.stop();
        screenAudioTrackRef.current.close();
        screenAudioTrackRef.current = null;
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
    setCameraOn(false);
    setSharingScreen(false);
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
      const cam = await AgoraRTC.createCameraVideoTrack(selectedCameraId ? { cameraId: selectedCameraId } : undefined);
      cameraTrackRef.current = cam;
      localVideoTrackRef.current = cam;
      await clientRef.current.publish([cam]);
      if (localVideoRef.current) cam.play(localVideoRef.current);
      setCameraOn(true);
      toast.success('Camera is live on Agora');
    } catch (err: any) {
      toast.error('Could not start camera', err?.message || 'Check camera permissions.');
    }
  }

  async function toggleScreenShare() {
    if (!clientRef.current) return;
    if (sharingScreen) {
      const tracks = [localVideoTrackRef.current, screenAudioTrackRef.current].filter(Boolean) as Array<ILocalVideoTrack | ILocalAudioTrack>;
      if (tracks.length) await clientRef.current.unpublish(tracks).catch(() => {});
      if (localVideoTrackRef.current) {
        localVideoTrackRef.current.stop();
        localVideoTrackRef.current.close();
      }
      if (screenAudioTrackRef.current) {
        screenAudioTrackRef.current.stop();
        screenAudioTrackRef.current.close();
      }
      localVideoTrackRef.current = cameraTrackRef.current;
      screenAudioTrackRef.current = null;
      setSharingScreen(false);
      if (cameraTrackRef.current) {
        await clientRef.current.publish([cameraTrackRef.current]).catch(() => {});
        if (localVideoRef.current) cameraTrackRef.current.play(localVideoRef.current);
        setCameraOn(true);
      } else {
        setCameraOn(false);
      }
      toast.info('Screen sharing stopped');
      return;
    }

    try {
      const screenResult = await AgoraRTC.createScreenVideoTrack({ encoderConfig: '1080p_2' }, 'auto');
      const screenVideoTrack = Array.isArray(screenResult) ? screenResult[0] : screenResult;
      const screenAudioTrack = Array.isArray(screenResult) ? screenResult[1] : null;

      if (cameraTrackRef.current) {
        await clientRef.current.unpublish([cameraTrackRef.current]).catch(() => {});
        cameraTrackRef.current.stop();
      }

      localVideoTrackRef.current = screenVideoTrack;
      screenAudioTrackRef.current = screenAudioTrack;
      const tracks = [screenVideoTrack, screenAudioTrack].filter(Boolean) as Array<ILocalVideoTrack | ILocalAudioTrack>;
      await clientRef.current.publish(tracks);
      if (localVideoRef.current) screenVideoTrack.play(localVideoRef.current);
      setSharingScreen(true);
      setCameraOn(false);
      screenVideoTrack.on('track-ended', () => {
        toggleScreenShare().catch(() => {});
      });
      toast.success('Screen sharing is live on Agora');
    } catch (err: any) {
      toast.error('Could not start screen sharing', err?.message || 'Check browser screen-share permissions.');
    }
  }

  async function changeMicrophone(deviceId: string) {
    setSelectedMicId(deviceId);
    if (!micTrackRef.current || !deviceId) return;
    try {
      await micTrackRef.current.setDevice(deviceId);
      toast.success('Microphone switched');
    } catch (err: any) {
      toast.error('Could not switch microphone', err?.message || 'Try another device.');
    }
  }

  async function changeCamera(deviceId: string) {
    setSelectedCameraId(deviceId);
    if (!cameraTrackRef.current || !deviceId || sharingScreen) return;
    try {
      await cameraTrackRef.current.setDevice(deviceId);
      toast.success('Camera switched');
    } catch (err: any) {
      toast.error('Could not switch camera', err?.message || 'Try another device.');
    }
  }

  async function changeSpeaker(deviceId: string) {
    setSelectedSpeakerId(deviceId);
    if (!deviceId) return;
    try {
      await Promise.all(remoteUsers.map(async (user) => {
        const track = user.audioTrack as IRemoteAudioTrack | undefined;
        if (track?.setPlaybackDevice) await track.setPlaybackDevice(deviceId);
      }));
      toast.success('Speaker output switched');
    } catch (err: any) {
      toast.error('Could not switch speaker output', err?.message || 'Your browser may not support output device switching.');
    }
  }

  async function hangUp() {
    await disconnect();
    navigate('/calls', { replace: true });
  }

  const otherParticipants = (activeCall?.participants || []).filter((p: any) => p.user?.id !== me.id);
  const timerText = new Date(seconds * 1000).toISOString().slice(14, 19);
  const localVideoActive = cameraOn || sharingScreen;
  const localShareLabel = sharingScreen ? ' · presenting live' : '';

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
            <div className="cr__video-label">You {sharingScreen ? '· screen sharing' : cameraOn ? '· camera on' : '· audio only'}{localShareLabel}</div>
            <div ref={localVideoRef} className={`cr__video-surface ${localVideoActive ? 'has-video' : ''}`}>
              {sharingScreen && <span className="cr__live-chip">Sharing screen</span>}
              {!localVideoActive && <div className="cr__video-placeholder"><Avatar name={me.name} src={me.avatarUrl} isClient={me.isClient} size={56} /></div>}
            </div>
          </div>
          {otherParticipants.map((p: any) => {
            const remoteUser = remoteUsers.find((u) => String(u.uid) === p.user.id);
            const remoteHasVideo = !!remoteUser?.videoTrack;
            return (
              <div key={`video-${p.user.id}`} className="cr__video-card">
                <div className="cr__video-label">{p.user.name} {remoteHasVideo ? '· video live' : '· audio only'}</div>
                <div ref={(el) => { remoteVideoRefs.current[p.user.id] = el; }} className={`cr__video-surface ${remoteHasVideo ? 'has-video' : ''}`}>
                  {remoteHasVideo && <span className="cr__live-chip">Live video</span>}
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
                <div className="cr__person-sub">You {muted ? '· muted' : '· microphone on'}{sharingScreen ? ' · sharing screen' : cameraOn ? ' · camera live' : ''}</div>
              </div>
            </article>
            {otherParticipants.map((p: any) => {
              const remoteJoined = remoteUsers.some((u) => String(u.uid) === p.user.id);
              return (
                <article key={p.user.id} className="cr__person">
                  <Avatar name={p.user.name} src={p.user.avatarUrl} isClient={p.user.isClient} size={42} />
                  <div>
                    <UserName name={p.user.name} isClient={p.user.isClient} role={p.user.role} />
                    <div className="cr__person-sub">{remoteJoined ? 'Live in Agora room' : 'Waiting to join'}{remoteUsers.find((u) => String(u.uid) === p.user.id)?.videoTrack ? ' · video live' : ''}</div>
                  </div>
                  <span className={`cr__presence ${remoteJoined ? 'is-live' : ''}`}>
                    <Volume2 size={14} /> {remoteJoined ? 'Connected' : 'Pending'}
                  </span>
                </article>
              );
            })}
          </div>
        </div>

        <div className="cr__devices">
          <div className="cr__device">
            <label className="cr__device-label">Microphone</label>
            <select className="cr__device-select" value={selectedMicId} onChange={(e) => changeMicrophone(e.target.value)} disabled={!microphones.length}>
              {microphones.length ? microphones.map((device) => <option key={device.deviceId} value={device.deviceId}>{device.label || 'Microphone'}</option>) : <option value="">Default microphone</option>}
            </select>
          </div>
          <div className="cr__device">
            <label className="cr__device-label">Camera</label>
            <select className="cr__device-select" value={selectedCameraId} onChange={(e) => changeCamera(e.target.value)} disabled={!cameras.length || sharingScreen}>
              {cameras.length ? cameras.map((device) => <option key={device.deviceId} value={device.deviceId}>{device.label || 'Camera'}</option>) : <option value="">Default camera</option>}
            </select>
          </div>
          <div className="cr__device">
            <label className="cr__device-label">Speaker output</label>
            <select className="cr__device-select" value={selectedSpeakerId} onChange={(e) => changeSpeaker(e.target.value)} disabled={!speakers.length}>
              {speakers.length ? speakers.map((device) => <option key={device.deviceId} value={device.deviceId}>{device.label || 'Speaker'}</option>) : <option value="">Default speaker</option>}
            </select>
          </div>
        </div>

        <div className="cr__actions">
          <Button variant={muted ? 'secondary' : 'ghost'} onClick={toggleMute} disabled={!joined || connecting}>
            {muted ? <MicOff size={16} /> : <Mic size={16} />} {muted ? 'Unmute' : 'Mute'}
          </Button>
          <Button variant={cameraOn ? 'secondary' : 'ghost'} onClick={toggleCamera} disabled={!joined || connecting || sharingScreen}>
            {cameraOn ? <CameraOff size={16} /> : <Camera size={16} />} {cameraOn ? 'Stop video' : 'Start video'}
          </Button>
          <Button variant={sharingScreen ? 'secondary' : 'ghost'} onClick={toggleScreenShare} disabled={!joined || connecting}>
            {sharingScreen ? <VolumeX size={16} /> : <MonitorUp size={16} />} {sharingScreen ? 'Stop share' : 'Share screen'}
          </Button>
          <Button variant="danger" onClick={hangUp}>
            <PhoneOff size={16} /> Leave call
          </Button>
        </div>
      </section>
    </div>
  );
}
