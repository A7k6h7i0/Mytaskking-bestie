import { useEffect, useMemo, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import axios from 'axios';
import AgoraRTC, {
  IAgoraRTCClient,
  IAgoraRTCRemoteUser,
  ICameraVideoTrack,
  IMicrophoneAudioTrack,
} from 'agora-rtc-sdk-ng';
import { Camera, CameraOff, Copy, Link2, Mic, MicOff, PhoneOff, Users, Video } from 'lucide-react';
import { api, apiUrl } from '@/services/api';
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
  token: string | null;
  channelName: string;
  uid: string | number;
  expiresAt: number | null;
  appId?: string;
  disabled?: boolean;
  room: MeetingRoom;
  guestName?: string;
};

type LobbyData = {
  room: MeetingRoom;
  participants: Array<{ id: string; displayName: string; joinedVia: string; joinedAt: string }>;
  shareHistory: Array<{ id: string; copiedByName: string; copiedAt: string }>;
  pendingRequests: Array<{ id: string; guestName: string; requestedAt: string; status: string }>;
};

const rtcClient = AgoraRTC.createClient({ mode: 'rtc', codec: 'vp8' });

export default function MeetingJoinPage() {
  const { slug = '' } = useParams();
  const me = useAuthStore((s) => s.user);
  const [guestName, setGuestName] = useState(me?.name || '');
  const [joined, setJoined] = useState(false);
  const [joining, setJoining] = useState(false);
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
    refetchInterval: joined ? 5_000 : 10_000,
  });
  const shareMut = useMutation({
    mutationFn: async () =>
      (await axios.post(`${apiUrl}/api/v1/meetings/public/${slug}/share`, { copiedByName: (guestName || 'Guest').trim() })).data,
    onSuccess: () => lobbyQuery.refetch(),
  });

  useEffect(() => {
    if (me?.name) setGuestName(me.name);
  }, [me?.name]);

  const meetingTitle = roomQuery.data?.name || 'Meeting room';
  const isVideoMode = useMemo(() => ['VIDEO', 'WEBINAR', 'LIVESTREAM'].includes(roomQuery.data?.mode || 'VIDEO'), [roomQuery.data?.mode]);
  const displayName = (me?.name || guestName || 'Guest').trim();

  async function copyShareLink() {
    const url = roomQuery.data?.shareUrl;
    if (!url) return;
    await navigator.clipboard.writeText(url);
    await shareMut.mutateAsync().catch(() => {});
    toast.success('Meeting link copied');
  }

  async function getMeetingToken() {
    if (me) {
      return (await api.post(`/meetings/${slug}/token`)).data as MeetingToken;
    }
    return (await axios.post(`${apiUrl}/api/v1/meetings/public/${slug}/token`, { guestName: displayName })).data as MeetingToken;
  }

  async function startMicrophone({ quiet = false } = {}) {
    if (!clientRef.current) return false;
    try {
      const mic = await AgoraRTC.createMicrophoneAudioTrack();
      micTrackRef.current = mic;
      await clientRef.current.publish([mic]);
      setMuted(false);
      return true;
    } catch (err: any) {
      setMuted(true);
      if (!quiet) {
        toast.warn('No microphone found', err?.message || 'You joined without audio.');
      }
      return false;
    }
  }

  async function joinMeeting() {
    if (joined || joining) return;
    if (!me && !displayName) {
      toast.warn('Enter your name first');
      return;
    }

    setJoining(true);
    try {
      const token = await getMeetingToken();
      if (token.disabled || !token.appId) {
        toast.error('Meeting video is not configured', 'Set AGORA_APP_ID and AGORA_APP_CERTIFICATE in backend .env.');
        return;
      }

      const client = rtcClient;
      clientRef.current = client;
      client.removeAllListeners();
      client.on('user-published', async (user, mediaType) => {
        await client.subscribe(user, mediaType);
        if (mediaType === 'audio') user.audioTrack?.play();
        setRemoteUsers([...client.remoteUsers]);
      });
      client.on('user-unpublished', (user) => {
        user.videoTrack?.stop();
        setRemoteUsers([...client.remoteUsers]);
      });
      client.on('user-joined', () => setRemoteUsers([...client.remoteUsers]));
      client.on('user-left', () => setRemoteUsers([...client.remoteUsers]));

      await client.join(token.appId, token.channelName, token.token, token.uid);
      await startMicrophone({ quiet: true });

      setJoined(true);
      setRemoteUsers([...client.remoteUsers]);
      lobbyQuery.refetch();
      toast.success(`Joined ${meetingTitle}`);
    } catch (err: any) {
      toast.error('Could not join meeting', err?.response?.data?.error?.message || err?.message || 'Please try again.');
      await leaveMeeting(true);
    } finally {
      setJoining(false);
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
    if (!clientRef.current) return;
    if (!micTrackRef.current) {
      await startMicrophone();
      return;
    }
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

    try {
      const cam = await AgoraRTC.createCameraVideoTrack();
      cameraTrackRef.current = cam;
      await clientRef.current.publish([cam]);
      if (localVideoRef.current) cam.play(localVideoRef.current);
      setCameraOn(true);
    } catch (err: any) {
      toast.error('Could not start camera', err?.message || 'Check camera permission.');
    }
  }

  useEffect(() => {
    if (cameraOn && cameraTrackRef.current && localVideoRef.current) {
      cameraTrackRef.current.play(localVideoRef.current);
    }
  }, [cameraOn]);

  useEffect(() => {
    remoteUsers.forEach((user) => {
      const el = remoteVideoRefs.current[String(user.uid)];
      if (el && user.videoTrack) user.videoTrack.play(el);
    });
  }, [remoteUsers]);

  useEffect(() => () => { leaveMeeting(true); }, []);

  return (
    <div className="mt mt--join">
      <header className="mt__head">
        <div>
          <h1>{meetingTitle}</h1>
          <p>Anyone with this link can join directly. Audio and video controls are available inside the room.</p>
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
          <div className="mt__prejoin">
            <div className="mt__prejoin-copy">
              <span className="mt__prejoin-badge"><Video size={14} /> {roomQuery.data?.mode || 'VIDEO'} room</span>
              <h2>Ready to join?</h2>
              <p>{me ? `Joining as ${me.name}` : 'Enter your name and jump straight into the meeting.'}</p>
            </div>
            {!me && (
              <Input label="Your name" value={guestName} onChange={(e) => setGuestName(e.target.value)} />
            )}
            <div className="mt__create-actions">
              <Button onClick={joinMeeting} loading={joining} disabled={roomQuery.isLoading || (!me && !displayName)}>
                <Video size={16} /> Join now
              </Button>
            </div>
          </div>
        ) : (
          <>
            <div className="mt__live-summary">
              <span><Users size={14} /> {remoteUsers.length + 1} connected</span>
              <span>{muted ? 'Microphone off' : 'Microphone on'}</span>
              <span>{isVideoMode ? (cameraOn ? 'Camera on' : 'Camera off') : 'Voice room'}</span>
            </div>
            <div className="cr__video-grid">
              <div className="cr__video-card cr__video-card--local">
                <div className="cr__video-label">You {muted ? '· muted' : '· mic on'}{cameraOn ? ' · camera on' : ''}</div>
                <div ref={localVideoRef} className={`cr__video-surface ${cameraOn ? 'has-video' : ''}`}>
                  {!cameraOn && <div className="cr__video-placeholder"><Avatar name={displayName} size={56} /></div>}
                </div>
              </div>
              {remoteUsers.map((user) => {
                const hasVideo = !!user.videoTrack;
                return (
                  <div key={String(user.uid)} className="cr__video-card">
                    <div className="cr__video-label">{String(user.uid).startsWith('guest_') ? 'Guest' : 'Participant'} {hasVideo ? '· video live' : '· audio only'}</div>
                    <div ref={(el) => { remoteVideoRefs.current[String(user.uid)] = el; }} className={`cr__video-surface ${hasVideo ? 'has-video' : ''}`}>
                      {!hasVideo && <div className="cr__video-placeholder"><Avatar name="Participant" size={56} /></div>}
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
                <PhoneOff size={16} /> Leave
              </Button>
            </div>
          </>
        )}
      </section>

      <section className="mt__join-card">
        <div className="mt__live-summary">
          <span><Users size={14} /> {lobbyQuery.data?.participants.length || 0} people have joined</span>
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
              {!lobbyQuery.data?.participants?.length && <div className="cn__directory-empty">No one has joined yet.</div>}
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
