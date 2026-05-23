import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Video, Phone, Plus, ExternalLink, Link2, Copy, Square } from 'lucide-react';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Skeleton } from '@/components/ui/Skeleton';
import { toast } from '@/components/Toast';
import './meetings.css';

dayjs.extend(relativeTime);

type Meeting = {
  id: string;
  slug: string;
  name: string;
  mode: 'VOICE' | 'VIDEO' | 'WEBINAR' | 'LIVESTREAM';
  channelName: string;
  hostId: string;
  scheduledAt: string | null;
  endedAt: string | null;
  createdAt: string;
  shareUrl: string;
};

export default function MeetingsPage() {
  const qc = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [form, setForm] = useState({ name: '', mode: 'VIDEO' as Meeting['mode'] });

  const { data, isLoading } = useQuery<{ items: Meeting[] }>({
    queryKey: ['meetings.mine'],
    queryFn: async () => (await api.get('/meetings')).data,
    refetchInterval: 15_000,
  });

  const createMut = useMutation({
    mutationFn: async () => (await api.post('/meetings', form)).data,
    onSuccess: (m) => {
      toast.success(`Room ready · ${m.slug}`);
      setShowNew(false);
      setForm({ name: '', mode: 'VIDEO' });
      qc.invalidateQueries({ queryKey: ['meetings.mine'] });
    },
    onError: () => toast.error('Could not create meeting'),
  });

  const endMut = useMutation({
    mutationFn: async (slug: string) => (await api.post(`/meetings/${slug}/end`)).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['meetings.mine'] }),
  });

  async function join(m: Meeting) {
    window.open(`/meetings/join/${m.slug}`, '_blank', 'noopener,noreferrer');
  }

  async function copyLink(url: string) {
    await navigator.clipboard.writeText(url);
    toast.success('Meeting link copied');
  }

  return (
    <div className="mt">
      <header className="mt__head">
        <div>
          <h1>Meetings</h1>
          <p>Voice + video rooms powered by Agora. Webinar and livestream modes share the same room primitive.</p>
        </div>
        <Button onClick={() => setShowNew((v) => !v)}><Plus size={16}/> New meeting</Button>
      </header>

      {showNew && (
        <div className="mt__create">
          <Input label="Name" placeholder="Design review" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <label className="mt__select">
            <span>Mode</span>
            <select value={form.mode} onChange={(e) => setForm({ ...form, mode: e.target.value as Meeting['mode'] })}>
              <option value="VOICE">Voice</option>
              <option value="VIDEO">Video</option>
              <option value="WEBINAR">Webinar</option>
              <option value="LIVESTREAM">Livestream</option>
            </select>
          </label>
          <div className="mt__create-actions">
            <Button variant="ghost" onClick={() => setShowNew(false)}>Cancel</Button>
            <Button loading={createMut.isPending} onClick={() => createMut.mutate()}>Create room</Button>
          </div>
        </div>
      )}

      <div className="mt__grid">
        {isLoading && Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} height={120} />)}
        {!isLoading && (data?.items || []).map((m) => (
          <article key={m.id} className={`mt__card mt__card--${m.mode.toLowerCase()}`}>
            <header>
              <div className="mt__mode">
                {m.mode === 'VOICE' ? <Phone size={14}/> : <Video size={14}/>}
                <span>{m.mode}</span>
              </div>
              <span className="mt__slug">{m.slug}</span>
            </header>
            <h3>{m.name}</h3>
            <p>
              {m.scheduledAt
                ? `Scheduled ${dayjs(m.scheduledAt).format('MMM D, HH:mm')}`
                : `Created ${dayjs(m.createdAt).fromNow()}`}
            </p>
            <div className="mt__card-link">
              <Link2 size={14} />
              <span>{m.shareUrl}</span>
              <button type="button" onClick={() => copyLink(m.shareUrl)}>
                <Copy size={14} /> Copy
              </button>
            </div>
            <footer>
              <Button size="sm" onClick={() => join(m)}>
                <ExternalLink size={14}/> Join
              </Button>
              <Button size="sm" variant="ghost" onClick={() => endMut.mutate(m.slug)}>
                <Square size={14}/> End
              </Button>
            </footer>
          </article>
        ))}
        {!isLoading && (data?.items.length ?? 0) === 0 && (
          <div className="mt__empty">No active rooms. Create one to start.</div>
        )}
      </div>
    </div>
  );
}
