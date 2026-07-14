import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Disc3,
  Phone,
  Video,
  Download,
  Trash2,
  Building2,
  Radio,
  Headset,
} from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { useConfirm } from '@/components/ui/ConfirmDialog';
import { toast } from '@/components/Toast';
import './calls.css';

type RecordingFile = {
  name: string;
  kind: 'audio' | 'video' | string;
  url: string;
  participantId?: string | null;
  size?: number | null;
};

type Recording = {
  id: string;
  source: 'CALL' | 'MEETING' | 'TELECALLER' | 'MEDIASOUP';
  title: string;
  recordingUrl: string | null;
  files?: RecordingFile[];
  participants: string[];
  startedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  roomId?: string | null;
  organisation?: { id: string; name: string; slug: string } | null;
};

function sourceLabel(source: Recording['source']) {
  switch (source) {
    case 'MEDIASOUP':
      return 'SFU call';
    case 'TELECALLER':
      return 'Telecaller';
    case 'MEETING':
      return 'Meeting';
    default:
      return 'Uploaded call';
  }
}

function sourceIcon(source: Recording['source']) {
  if (source === 'MEETING') return <Video size={18} />;
  if (source === 'TELECALLER') return <Headset size={18} />;
  if (source === 'MEDIASOUP') return <Radio size={18} />;
  return <Phone size={18} />;
}

function mediaFiles(r: Recording): RecordingFile[] {
  if (Array.isArray(r.files) && r.files.length) {
    return r.files.filter((f) => f?.url);
  }
  if (r.recordingUrl) {
    return [{ name: 'recording', kind: 'audio', url: r.recordingUrl }];
  }
  return [];
}

export default function RecordingsPage() {
  const user = useAuthStore((s) => s.user);
  const isPlatformAdmin = user?.role === 'SUPER_ADMIN';
  const [scope, setScope] = useState<'org' | 'platform'>('org');
  const qc = useQueryClient();
  const { confirm, ConfirmRenderer } = useConfirm();
  const { data, isLoading, isError } = useQuery<{
    items: Recording[];
    total: number;
    mediasoupConfigured?: boolean;
  }>({
    queryKey: ['recordings', scope],
    queryFn: async () =>
      (await api.get('/recordings', { params: { scope } })).data,
  });
  const deleteMut = useMutation({
    mutationFn: async (recording: Recording) =>
      api.delete(`/recordings/${recording.source}/${recording.id}`),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['recordings'] });
      toast.success('Recording deleted');
    },
    onError: () => toast.error('Could not delete recording'),
  });

  async function askDelete(recording: Recording) {
    const ok = await confirm({
      title: 'Delete recording?',
      description:
        recording.source === 'MEDIASOUP'
          ? `This deletes the SFU recording "${recording.title}" from connect.mytaskking.com.`
          : `This removes "${recording.title}" from the recordings list.`,
      confirmLabel: 'Delete',
      variant: 'danger',
    });
    if (ok) deleteMut.mutate(recording);
  }

  const items = data?.items || [];

  return (
    <div className="cl">
      <header className="cl__head">
        <div>
          <h1 className="cl__title">Recordings</h1>
          <p className="cl__sub">
            {scope === 'platform'
              ? 'All organisations — uploaded recordings plus connect SFU (calls.md) recordings.'
              : 'Uploaded call/meeting/telecaller recordings plus auto SFU call recordings.'}
          </p>
        </div>
        {isPlatformAdmin && (
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              type="button"
              className={`cl__person${scope === 'org' ? ' cl__person--active' : ''}`}
              onClick={() => setScope('org')}
            >
              My organisation
            </button>
            <button
              type="button"
              className={`cl__person${scope === 'platform' ? ' cl__person--active' : ''}`}
              onClick={() => setScope('platform')}
            >
              <Building2 size={14} style={{ marginRight: 4, verticalAlign: -2 }} />
              All organisations
            </button>
          </div>
        )}
      </header>

      <div className="cl__list">
        {items.map((r) => {
          const files = mediaFiles(r);
          const primary = files[0]?.url || r.recordingUrl || '';
          return (
            <article key={`${r.source}-${r.id}`} className="cl__row">
              <div className="cl__row-icon">{sourceIcon(r.source)}</div>
              <div className="cl__row-body">
                <div className="cl__row-title">
                  {r.title}{' '}
                  <span className="cl__status">{sourceLabel(r.source)}</span>
                  {r.organisation && (
                    <span className="cl__status" style={{ marginLeft: 8 }}>
                      {r.organisation.name}
                    </span>
                  )}
                </div>
                {!!r.participants?.length && (
                  <div className="cl__row-people">{r.participants.join(', ')}</div>
                )}
                {r.roomId && r.source === 'MEDIASOUP' && (
                  <div className="cl__row-people">Room · {r.roomId}</div>
                )}
                <div className="cl__recording-files">
                  {files.map((f) =>
                    f.kind === 'video' ? (
                      <div key={`${r.id}-${f.name}`} className="cl__media-block">
                        <div className="cl__media-label">
                          Video{f.participantId ? ` · ${f.participantId}` : ''}
                        </div>
                        <video
                          controls
                          preload="none"
                          src={f.url}
                          style={{
                            marginTop: 4,
                            width: '100%',
                            maxWidth: 420,
                            borderRadius: 8,
                            background: '#000',
                          }}
                        />
                        <a
                          href={f.url}
                          target="_blank"
                          rel="noreferrer"
                          className="cl__person"
                          style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: 6,
                            marginTop: 6,
                          }}
                        >
                          <Download size={14} /> Download video
                        </a>
                      </div>
                    ) : (
                      <div key={`${r.id}-${f.name}`} className="cl__media-block">
                        <div className="cl__media-label">
                          Audio{f.participantId ? ` · ${f.participantId}` : ''}
                        </div>
                        <audio
                          controls
                          preload="none"
                          src={f.url}
                          style={{ marginTop: 4, width: '100%', maxWidth: 420 }}
                        />
                        <a
                          href={f.url}
                          target="_blank"
                          rel="noreferrer"
                          className="cl__person"
                          style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: 6,
                            marginTop: 6,
                          }}
                        >
                          <Download size={14} /> Download audio
                        </a>
                      </div>
                    ),
                  )}
                  {!files.length && (
                    <div className="cl__row-people">No playable media files</div>
                  )}
                </div>
              </div>
              <div className="cl__row-meta">
                <div>{dayjs(r.createdAt).format('MMM D · HH:mm')}</div>
                {primary && files.length <= 1 && (
                  <a
                    href={primary}
                    target="_blank"
                    rel="noreferrer"
                    className="cl__person"
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 6,
                      marginTop: 6,
                    }}
                  >
                    <Download size={14} /> Download
                  </a>
                )}
                {(user?.role === 'SUPER_ADMIN' || user?.role === 'ADMIN') && (
                  <button
                    type="button"
                    className="cl__delete"
                    onClick={() => askDelete(r)}
                    disabled={deleteMut.isPending}
                    aria-label={`Delete ${r.title}`}
                  >
                    <Trash2 size={14} /> Delete
                  </button>
                )}
              </div>
            </article>
          );
        })}
        {isError && (
          <div className="cl__empty">Couldn&apos;t load recordings. Please try again.</div>
        )}
        {!isLoading && !isError && !items.length && (
          <div className="cl__empty">
            <Disc3 size={20} style={{ marginBottom: 6 }} />
            <div>
              No recordings yet. SFU calls are recorded automatically on connect;
              uploaded call/meeting/telecaller recordings also appear here.
            </div>
          </div>
        )}
      </div>
      <ConfirmRenderer />
    </div>
  );
}
