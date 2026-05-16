import { useQuery } from '@tanstack/react-query';
import { Hash, Users, Pin } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { api } from '@/services/api';
import './channels.css';

export default function ChannelsPage() {
  const navigate = useNavigate();
  const { data, isLoading } = useQuery<{ items: any[] }>({
    queryKey: ['channels.mine'],
    queryFn: async () => (await api.get('/channels')).data,
  });

  if (isLoading) return <div className="cn__loading">Loading channels…</div>;

  return (
    <div className="cn">
      <header className="cn__head">
        <div>
          <h1 className="cn__title">Channels</h1>
          <p className="cn__sub">Pinned conversations, team channels, projects, and client workspaces.</p>
        </div>
      </header>

      <div className="cn__grid">
        {data?.items.map((c) => (
          <article key={c.id} className="cn__card" onClick={() => navigate(`/chat/${c.id}`)}>
            <header className="cn__card-head">
              <div className="cn__card-name">
                <Hash size={16} />
                <span className={c.isClientChannel ? 'client-name' : ''}>{c.name || 'Direct message'}</span>
                {c.pinned && <Pin size={12} className="cn__pin" />}
              </div>
              <span className={`cn__kind cn__kind--${c.kind.toLowerCase()}`}>{c.kind}</span>
            </header>
            <p className="cn__desc">{c.description || 'No description'}</p>
            <footer className="cn__card-foot">
              <span><Users size={12} /> {c.members?.length || 0}</span>
              <span>{c._count?.messages || 0} messages</span>
            </footer>
          </article>
        ))}
        {data?.items.length === 0 && <div className="cn__empty">No channels yet. Ask an admin to add you.</div>}
      </div>
    </div>
  );
}
