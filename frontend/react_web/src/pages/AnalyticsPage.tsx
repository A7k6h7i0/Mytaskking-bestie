import { useQuery } from '@tanstack/react-query';
import { TrendingUp, MessageSquare, Phone, KanbanSquare, Users } from 'lucide-react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Skeleton } from '@/components/ui/Skeleton';
import { Leaderboard } from '@/components/Leaderboard';
import './analytics.css';

export default function AnalyticsPage() {
  const productivity = useQuery<{ items: Array<{ user: any; completed: number }> }>({
    queryKey: ['analytics.productivity'],
    queryFn: async () => (await api.get('/analytics/productivity')).data,
  });
  const telecaller = useQuery<{ items: Array<{ agent: any; calls: number; totalDurationSec: number; leadsWon: number }> }>({
    queryKey: ['analytics.telecaller'],
    queryFn: async () => (await api.get('/analytics/telecaller')).data,
  });
  const tasks = useQuery<{ byStatus: Record<string, number>; overdue: number }>({
    queryKey: ['analytics.tasks'],
    queryFn: async () => (await api.get('/analytics/tasks')).data,
  });
  const workspace = useQuery<{ messages: number; activeUsers: number; calls: number; telecallerSeconds: number }>({
    queryKey: ['analytics.workspace'],
    queryFn: async () => (await api.get('/analytics/workspace')).data,
  });

  return (
    <div className="an">
      <header className="an__head">
        <div>
          <h1>Analytics</h1>
          <p>Productivity, telecaller performance, task throughput, and engagement over the last 30 days.</p>
        </div>
      </header>

      <div className="an__row">
        <Kpi icon={MessageSquare} label="Messages" value={workspace.data?.messages} color="brand" />
        <Kpi icon={Users} label="Active users" value={workspace.data?.activeUsers} color="success" />
        <Kpi icon={Phone} label="Voice calls" value={workspace.data?.calls} color="info" />
        <Kpi icon={KanbanSquare} label="Tasks overdue" value={tasks.data?.overdue} color="warning" />
      </div>

      <Leaderboard />

      <section className="an__section">
        <header><h3><TrendingUp size={16}/> Top contributors — tasks completed</h3></header>
        <div className="an__bars">
          {productivity.isLoading && Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} height={26} />)}
          {productivity.data?.items.slice(0, 8).map((r) => (
            <BarRow key={r.user?.id || Math.random()}
              avatar={<Avatar name={r.user?.name || '?'} src={r.user?.avatarUrl} isClient={r.user?.isClient} size={26} />}
              name={<UserName name={r.user?.name || 'Unknown'} isClient={r.user?.isClient} role={r.user?.role} />}
              value={r.completed}
              max={Math.max(...(productivity.data?.items.map((x) => x.completed) || [1]))}
            />
          ))}
          {!productivity.isLoading && (productivity.data?.items.length ?? 0) === 0 && <div className="an__empty">No completed tasks in this window yet.</div>}
        </div>
      </section>

      <section className="an__section">
        <header><h3><Phone size={16}/> Telecaller performance</h3></header>
        <table className="an__table">
          <thead><tr><th>Agent</th><th>Calls</th><th>Talk time</th><th>Leads won</th></tr></thead>
          <tbody>
            {telecaller.data?.items.map((r) => (
              <tr key={r.agent?.id || Math.random()}>
                <td><Avatar name={r.agent?.name || '?'} size={22} /> {r.agent?.name || '—'}</td>
                <td>{r.calls}</td>
                <td>{Math.floor((r.totalDurationSec || 0) / 60)}m</td>
                <td>{r.leadsWon}</td>
              </tr>
            ))}
            {telecaller.data?.items.length === 0 && (
              <tr><td colSpan={4} className="an__empty">No calls in this window.</td></tr>
            )}
          </tbody>
        </table>
      </section>

      <section className="an__section">
        <header><h3><KanbanSquare size={16}/> Task throughput</h3></header>
        <div className="an__pills">
          {Object.entries(tasks.data?.byStatus || {}).map(([s, n]) => (
            <span key={s} className={`an__pill an__pill--${s.toLowerCase()}`}>{s} · {n}</span>
          ))}
          {!tasks.data && <Skeleton height={28} />}
        </div>
      </section>
    </div>
  );
}

function Kpi({ icon: Icon, label, value, color }: { icon: any; label: string; value: any; color: string }) {
  return (
    <div className={`an__kpi an__kpi--${color}`}>
      <div className="an__kpi-icon"><Icon size={18}/></div>
      <div>
        <div className="an__kpi-label">{label}</div>
        <div className="an__kpi-value">{value ?? '—'}</div>
      </div>
    </div>
  );
}

function BarRow({ avatar, name, value, max }: { avatar: React.ReactNode; name: React.ReactNode; value: number; max: number }) {
  const pct = max ? Math.max(2, Math.round((value / max) * 100)) : 0;
  return (
    <div className="an__bar-row">
      <div className="an__bar-label">{avatar} {name}</div>
      <div className="an__bar-track"><div className="an__bar-fill" style={{ width: `${pct}%` }} /></div>
      <div className="an__bar-val">{value}</div>
    </div>
  );
}
