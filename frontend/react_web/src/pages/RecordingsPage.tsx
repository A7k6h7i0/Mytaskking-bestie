import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Disc3, Phone, Video, Download, Trash2, Building2 } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { useConfirm } from '@/components/ui/ConfirmDialog';
import { toast } from '@/components/Toast';
import './calls.css';

type Recording = {
  id: string;
  source: 'CALL' | 'MEETING';
  title: string;
  recordingUrl: string;
  participants: string[];
  startedAt: string | null;
  endedAt: string | null;
  createdAt: string;
  organisation?: { id: string; name: string; slug: string } | null;
};

export default function RecordingsPage() {
  const user = useAuthStore((s) => s.user);
  const isPlatformAdmin = user?.role === 'SUPER_ADMIN';
  const [scope, setScope] = useState<'org' | 'platform'>('org');
  const qc = useQueryClient();
  const { confirm, ConfirmRenderer } = useConfirm();
  const { data, isLoading, isError } = useQuery<{ items: Recording[]; total: number }>({
    queryKey: ['recordings', scope],
    queryFn: async () => (await api.get('/recordings', { params: { scope } })).data,
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
      description: `This removes "${recording.title}" from the recordings list.`,
      confirmLabel: 'Delete',
      variant: 'danger',
    });
    if (ok) deleteMut.mutate(recording);
  }

  return (
    <div className="cl">
      <header className="cl__head">
        <div>
          <h1 className="cl__title">Recordings</h1>
          <p className="cl__sub">
            {scope === 'platform'
              ? 'All organisations — platform view (super admin only).'
              : 'Saved audio from calls and meetings in your organisation.'}
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
        {(data?.items || []).map((r) => (
          <article key={`${r.source}-${r.id}`} className="cl__row">
            <div className="cl__row-icon">
              {r.source === 'MEETING' ? <Video size={18} /> : <Phone size={18} />}
            </div>
            <div className="cl__row-body">
              <div className="cl__row-title">
                {r.title} · <span className="cl__status">{r.source}</span>
                {r.organisation && (
                  <span className="cl__status" style={{ marginLeft: 8 }}>
                    {r.organisation.name}
                  </span>
                )}
              </div>
              {!!r.participants.length && (
                <div className="cl__row-people">{r.participants.join(', ')}</div>
              )}
              <audio controls preload="none" src={r.recordingUrl} style={{ marginTop: 8, width: '100%', maxWidth: 420 }} />
            </div>
            <div className="cl__row-meta">
              <div>{dayjs(r.createdAt).format('MMM D · HH:mm')}</div>
              <a
                href={r.recordingUrl}
                target="_blank"
                rel="noreferrer"
                className="cl__person"
                style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginTop: 6 }}
              >
                <Download size={14} /> Download
              </a>
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
        ))}
        {isError && (
          <div className="cl__empty">Couldn't load recordings. Please try again.</div>
        )}
        {!isLoading && !isError && !data?.items.length && (
          <div className="cl__empty">
            <Disc3 size={20} style={{ marginBottom: 6 }} />
            <div>No recordings yet. Tap Record during a call or meeting to capture one.</div>
          </div>
        )}
      </div>
      <ConfirmRenderer />
    </div>
  );
}
