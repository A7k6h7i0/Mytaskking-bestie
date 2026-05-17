import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { Phone, PhoneIncoming, Users } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import './calls.css';

export default function CallsPage() {
  const navigate = useNavigate();
  const { data } = useQuery<{ items: any[] }>({
    queryKey: ['calls.history'],
    queryFn: async () => (await api.get('/calls/history')).data,
  });

  return (
    <div className="cl">
      <header className="cl__head">
        <div>
          <h1 className="cl__title">Calls</h1>
          <p className="cl__sub">One-to-one and group voice calls powered by Agora.</p>
        </div>
      </header>

      <div className="cl__list">
        {data?.items.map((c) => (
          <article key={c.id} className="cl__row">
            <div className="cl__row-icon">
              {c.kind === 'GROUP' ? <Users size={18} /> : c.status === 'MISSED' ? <PhoneIncoming size={18} /> : <Phone size={18} />}
            </div>
            <div className="cl__row-body">
              <div className="cl__row-title">
                {c.kind === 'GROUP' ? 'Group call' : 'One-to-one call'} ·{' '}
                <span className={`cl__status cl__status--${c.status.toLowerCase()}`}>{c.status}</span>
              </div>
              {c.status === 'MISSED' && <div className="cl__missed">Missed call — no one joined before the ring ended.</div>}
              <div className="cl__row-people">
                {c.participants.slice(0, 5).map((p: any) => (
                  <span key={p.user.id} className="cl__person">
                    <Avatar name={p.user.name} src={p.user.avatarUrl} isClient={p.user.isClient} size={22} />
                    <UserName name={p.user.name} isClient={p.user.isClient} role={p.user.role} />
                  </span>
                ))}
              </div>
            </div>
            <div className="cl__row-meta">
              <div>{dayjs(c.createdAt).format('MMM D · HH:mm')}</div>
              {(c.status === 'RINGING' || c.status === 'ACTIVE') && (
                <Button size="sm" variant="ghost" onClick={() => navigate(`/calls/live/${c.id}`)}>Join room</Button>
              )}
            </div>
          </article>
        ))}
        {!data?.items.length && <div className="cl__empty">No call history yet.</div>}
      </div>
    </div>
  );
}
