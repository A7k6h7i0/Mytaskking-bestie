import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Activity, Search, Filter, Radio } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { getSocket } from '@/services/socket';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Input } from '@/components/ui/Input';
import { SkeletonText } from '@/components/ui/Skeleton';
import './activity.css';

type LogItem = {
  id: string;
  kind: string;
  entity: string | null;
  entityId: string | null;
  payload: any;
  createdAt: string;
  actor: { id: string; name: string; role: string; avatarUrl?: string | null; isClient?: boolean } | null;
};

export default function ActivityPage() {
  const [q, setQ] = useState('');
  const [kind, setKind] = useState('');
  const [live, setLive] = useState(true);
  const qc = useQueryClient();

  const { data, isLoading } = useQuery<{ items: LogItem[]; nextCursor: string | null }>({
    queryKey: ['audit.log', q, kind],
    queryFn: async () => (await api.get('/audit', { params: { q: q || undefined, kind: kind || undefined } })).data,
  });

  // Realtime tail — server fires `activity.recorded` whenever a new audit row
  // lands. We invalidate the query so the timeline keeps streaming.
  useEffect(() => {
    if (!live) return;
    const s = getSocket();
    if (!s) return;
    const onRecorded = () => qc.invalidateQueries({ queryKey: ['audit.log', q, kind] });
    s.on('activity.recorded', onRecorded);
    return () => { s.off('activity.recorded', onRecorded); };
  }, [live, q, kind, qc]);

  return (
    <div className="ac">
      <header className="ac__head">
        <div>
          <h1>Activity</h1>
          <p>Complete audit trail across the workspace.</p>
        </div>
        <button
          className={'ac__live' + (live ? ' is-on' : '')}
          onClick={() => setLive((v) => !v)}
          title={live ? 'Pause realtime updates' : 'Resume realtime updates'}
        >
          <Radio size={14} /> {live ? 'Live' : 'Paused'}
        </button>
      </header>

      <div className="ac__filters">
        <Input leading={<Search size={14} />} placeholder="Search by kind, entity, id" value={q} onChange={(e) => setQ(e.target.value)} />
        <Input leading={<Filter size={14} />} placeholder="Filter by kind (e.g. task.)" value={kind} onChange={(e) => setKind(e.target.value)} />
      </div>

      <div className="ac__timeline">
        {isLoading && <SkeletonText lines={6} />}
        {!isLoading && data?.items.map((it) => (
          <div key={it.id} className="ac__row">
            <div className="ac__dot" />
            <div className="ac__when">{dayjs(it.createdAt).format('MMM D · HH:mm:ss')}</div>
            <Avatar
              name={it.actor?.name || 'System'}
              src={it.actor?.avatarUrl}
              isClient={it.actor?.isClient}
              size={26}
            />
            <div className="ac__details">
              <div className="ac__primary">
                <UserName
                  name={it.actor?.name || 'System'}
                  isClient={it.actor?.isClient}
                  role={it.actor?.role}
                />
                <span className="ac__kind">{it.kind}</span>
                {it.entity && <span className="ac__entity">{it.entity}{it.entityId ? ` · ${it.entityId.slice(0, 8)}…` : ''}</span>}
              </div>
              {it.payload && (
                <pre className="ac__payload">{JSON.stringify(it.payload, null, 0).slice(0, 240)}</pre>
              )}
            </div>
          </div>
        ))}
        {!isLoading && data?.items.length === 0 && (
          <div className="ac__empty"><Activity size={20} /><span>Nothing logged yet — actions will appear here in realtime.</span></div>
        )}
      </div>
    </div>
  );
}
