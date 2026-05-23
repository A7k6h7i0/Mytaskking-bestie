import { useEffect, useMemo, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import axios from 'axios';
import AgoraRTC, { IAgoraRTCClient, ICameraVideoTrack, IAgoraRTCRemoteUser, IMicrophoneAudioTrack } from 'agora-rtc-sdk-ng';
import { Camera, CameraOff, Copy, Link2, Mic, MicOff, PhoneOff, Users, Video } from 'lucide-react';
import { apiUrl } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Avatar } from '@/components/ui/Avatar';
import { toast } from '@/components/Toast';
import './meetings.css';
import './call-room.css';

type MeetingRoom = {
  id: string;
  slug: string;
  name: string;
  mode: 'VOICE' | 'VIDEO' | 'WEBINAR' | 'LIVESTREAM';
  shareUrl: string;
};

type MeetingToken = {
  token: string;
  channelName: string;
  uid: string;
  expiresAt: number;
  appId: string;
  room: MeetingRoom;
  guestName?: string;
};

type LobbyData = {
  room: MeetingRoom;
  participants: Array<{ id: string; displayName: string; joinedVia: string; joinedAt: string }>;
  shareHistory: Array<{ id: string; copiedByName: string; copiedAt: string }>;
};

const rtcClient = AgoraRTC.createClient({ mode: 'rtc', codec: 'vp8' });

export default function MeetingJoinPage() {
  const { slug = '' } = useParams();
  const me = useAuthStore((s) => s.user);
  const [guestName, setGuestName] = useState(me?.name || '');
  const [joined, setJoined] = useState(false);
  const [muted, setMuted] = useState(false);
  const [cameraOn, setCameraOn] = useState(false);
  const [remoteUsers, setRemoteUsers] = useState<IAgoraRTCRemoteUser[]>([]);
  const clientRef = useRef<IAgoraRTCClient | null>(null);
  const micTrackRef = useRef<IMicrophoneAudioTrack | null>(null);
  const cameraTrackRef = useRef<ICameraVideoTrack | null>(null);
  const localVideoRef = useRef<HTMLDivElement | null>(null);
  const remoteVideoRefs = useRef<Record<string, HTMLDivElement | null>>({});

  const roomQuery = useQuery<MeetingRoom>({
    queryKey: ['meeting.public', slug],
    queryFn: async () => (await axios.get(`${apiUrl}/api/v1/meetings/public/${slug}`)).data,
    enabled: !!slug,
  });
  const lobbyQuery = useQuery<LobbyData>({
    queryKey: ['meeting.public.lobby', slug],
    queryFn: async () => (await axios.get(`${apiUrl}/api/v1/meetings/public/${slug}/lobby`)).data,
    enabled: !!slug,
    refetchInterval: 10_000,
  });

  const tokenMut = useMutation({
    mutationFn: async () => (await axios.post(`${apiUrl}/api/v1/meetings/public/${slug}/token`, { guestName: guestName.trim() })).data as MeetingToken,
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not join meeting'),
  });
  const shareMut = useMutation({
    mutationFn: async () =>
      (await axios.post(`${apiUrl}/api/v1/meetings/public/${slug}/share`, { copiedByName: (guestName || 'Guest').trim() })).data,
    onSuccess: () => lobbyQuery.refetch(),
  });

  const meetingTitle = roomQuery.data?.name || 'Meeting room';
  const isVideoMode = useMemo(() => ['VIDEO', 'WEBINAR', 'LIVESTREAM'].includes(roomQuery.data?.mode || 'VIDEO'), [roomQuery.data?.mode]);

  async function copyShareLink() {
    const url = roomQuery.data?.shareUrl;
    if (!url) return;
    await navigator.clipboard.writeText(url);
    await shareMut.mutateAsync().catch(() => {});
    toast.success('Meeting link copied');
  }

  async function joinMeeting() {
    if (!guestName.trim()) {
      toast.warn('Enter your name first');
      return;
    }
    const token = await tokenMut.mutateAsync();
    try {
      const client = rtcClient;
      clientRef.current = client;
      client.removeAllListeners();
      client.on('user-published', async (user, mediaType) => {
        await client.subscribe(user, mediaType);
        if (mediaType === 'audio') user.audioTrack?.play();
        if (mediaType === 'video') {
          const el = remoteVideoRefs.current[String(user.uid)];
          if (el) user.videoTrack?.play(el);
        }
        setRemoteUsers([...client.remoteUsers]);
      });
      client.on('user-unpublished', (user) => {
        user.videoTrack?.stop();
        setRemoteUsers([...client.remoteUsers]);
      });
      client.on('user-joined', () => setRemoteUsers([...client.remoteUsers]));
      client.on('user-left', () => setRemoteUsers([...client.remoteUsers]));

      await client.join(token.appId, token.channelName, token.token, token.uid);
      const mic = await AgoraRTC.createMicrophoneAudioTrack();
      micTrackRef.current = mic;
      await client.publish([mic]);

      if (isVideoMode) {
        const cam = await AgoraRTC.createCameraVideoTrack();
        cameraTrackRef.current = cam;
        await client.publish([cam]);
        if (localVideoRef.current) cam.play(localVideoRef.current);
        setCameraOn(true);
      }

      setJoined(true);
      setRemoteUsers([...client.remoteUsers]);
      toast.success(`Joined ${meetingTitle}`);
    } catch (err: any) {
      toast.error('Could not start the meeting room', err?.message || 'Please try again.');
      await leaveMeeting(true);
    }
  }

  async function leaveMeeting(silent = false) {
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
    setJoined(false);
    setCameraOn(false);
    setMuted(false);
    setRemoteUsers([]);
    if (!silent) toast.info('You left the meeting');
  }

  async function toggleMute() {
    if (!micTrackRef.current) return;
    const next = !muted;
    await micTrackRef.current.setEnabled(!next);
    setMuted(next);
  }

  async function toggleCamera() {
    if (!clientRef.current) return;
    if (cameraOn && cameraTrackRef.current) {
      await clientRef.current.unpublish([cameraTrackRef.current]);
      cameraTrackRef.current.stop();
      cameraTrackRef.current.close();
      cameraTrackRef.current = null;
      setCameraOn(false);
      return;
    }
    const cam = await AgoraRTC.createCameraVideoTrack();
    cameraTrackRef.current = cam;
    await clientRef.current.publish([cam]);
    if (localVideoRef.current) cam.play(localVideoRef.current);
    setCameraOn(true);
  }

  useEffect(() => () => { leaveMeeting(true); }, []);

  return (
    <div className="mt mt--join">
      <header className="mt__head">
        <div>
          <h1>{meetingTitle}</h1>
          <p>Share the meeting URL with anyone. Guests can join directly from the browser without a workspace account.</p>
        </div>
        {roomQuery.data?.shareUrl && (
          <Button variant="ghost" onClick={copyShareLink}>
            <Copy size={16} /> Copy invite link
          </Button>
        )}
      </header>

      <section className="mt__join-card">
        {roomQuery.data?.shareUrl && (
          <div className="mt__card-link">
            <Link2 size={14} />
            <span>{roomQuery.data.shareUrl}</span>
          </div>
        )}
        {!joined ? (
          <div className="mt__join-form">
            <Input label="Your name" value={guestName} onChange={(e) => setGuestName(e.target.value)} />
            <div className="mt__create-actions">
              <Button onClick={joinMeeting} loading={tokenMut.isPending} disabled={!guestName.trim()}>
                <Video size={16} /> Join meeting
              </Button>
            </div>
          </div>
        ) : (
          <>
            <div className="mt__live-summary">
              <span><Users size={14} /> {remoteUsers.length + 1} people in room</span>
              <span>{roomQuery.data?.mode || 'VIDEO'} mode</span>
            </div>
            <div className="cr__video-grid">
              <div className="cr__video-card cr__video-card--local">
                <div className="cr__video-label">You</div>
                <div ref={localVideoRef} className={`cr__video-surface ${cameraOn ? 'has-video' : ''}`}>
                  {!cameraOn && <div className="cr__video-placeholder"><Avatar name={guestName} size={56} /></div>}
                </div>
              </div>
              {remoteUsers.map((user) => {
                const hasVideo = !!user.videoTrack;
                return (
                  <div key={String(user.uid)} className="cr__video-card">
                    <div className="cr__video-label">Participant</div>
                    <div ref={(el) => { remoteVideoRefs.current[String(user.uid)] = el; }} className={`cr__video-surface ${hasVideo ? 'has-video' : ''}`}>
                      {!hasVideo && <div className="cr__video-placeholder"><Avatar name="Guest" size={56} /></div>}
                    </div>
                  </div>
                );
              })}
            </div>
            <div className="cr__actions">
              <Button variant={muted ? 'secondary' : 'ghost'} onClick={toggleMute}>
                {muted ? <MicOff size={16} /> : <Mic size={16} />} {muted ? 'Unmute' : 'Mute'}
              </Button>
              {isVideoMode && (
                <Button variant={cameraOn ? 'secondary' : 'ghost'} onClick={toggleCamera}>
                  {cameraOn ? <CameraOff size={16} /> : <Camera size={16} />} {cameraOn ? 'Stop video' : 'Start video'}
                </Button>
              )}
              <Button variant="danger" onClick={() => leaveMeeting()}>
                <PhoneOff size={16} /> Leave meeting
              </Button>
            </div>
          </>
        )}
      </section>

      <section className="mt__join-card">
        <div className="mt__live-summary">
          <span><Users size={14} /> {lobbyQuery.data?.participants.length || 0} people seen in this room</span>
          <span><Copy size={14} /> {lobbyQuery.data?.shareHistory.length || 0} link copy events</span>
        </div>
        <div className="mt__lobby-grid">
          <div>
            <h3 className="mt__lobby-title">Participants</h3>
            <div className="mt__lobby-list">
              {(lobbyQuery.data?.participants || []).map((person) => (
                <div key={person.id} className="mt__lobby-row">
                  <Avatar name={person.displayName} size={26} />
                  <div>
                    <strong>{person.displayName}</strong>
                    <span>{person.joinedVia} · {new Date(person.joinedAt).toLocaleString()}</span>
                  </div>
                </div>
              ))}
              {!lobbyQuery.data?.participants?.length && <div className="cn__directory-empty">No participants have joined yet.</div>}
            </div>
          </div>
          <div>
            <h3 className="mt__lobby-title">Copy-link history</h3>
            <div className="mt__lobby-list">
              {(lobbyQuery.data?.shareHistory || []).map((share) => (
                <div key={share.id} className="mt__lobby-row">
                  <Avatar name={share.copiedByName} size={26} />
                  <div>
                    <strong>{share.copiedByName}</strong>
                    <span>{new Date(share.copiedAt).toLocaleString()}</span>
                  </div>
                </div>
              ))}
              {!lobbyQuery.data?.shareHistory?.length && <div className="cn__directory-empty">No one has copied this invite yet.</div>}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
