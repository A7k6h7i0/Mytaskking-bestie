import { useQuery } from '@tanstack/react-query';
import { Disc3, Phone, Video, Download } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
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
};

export default function RecordingsPage() {
  const { data, isLoading, isError } = useQuery<{ items: Recording[]; total: number }>({
    queryKey: ['recordings'],
    queryFn: async () => (await api.get('/recordings')).data,
  });

  return (
    <div className="cl">
      <header className="cl__head">
        <div>
          <h1 className="cl__title">Recordings</h1>
          <p className="cl__sub">Saved audio from calls and meeting rooms across the workspace.</p>
        </div>
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
    </div>
  );
}
