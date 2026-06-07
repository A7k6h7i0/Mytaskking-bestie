import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { PhoneCall, PhoneIncoming, PhoneOutgoing, Download, Users, Clock } from 'lucide-react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Skeleton } from '@/components/ui/Skeleton';
import './talk-time.css';

type EmployeeRow = {
  rank: number;
  userId: string;
  name: string;
  role: string;
  customTitle?: string | null;
  avatarUrl?: string | null;
  totalSeconds: number;
  incomingSeconds: number;
  outgoingSeconds: number;
  calls: number;
  missed: number;
};

type OrgReport = {
  from: string;
  to: string;
  totalCombinedSeconds: number;
  averageSeconds: number;
  employeeCount: number;
  employees: EmployeeRow[];
};

function fmtDuration(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

function isoDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export default function TalkTimePage() {
  const [from, setFrom] = useState(() => isoDay(new Date(Date.now() - 29 * 86400000)));
  const [to, setTo] = useState(() => isoDay(new Date()));

  const { data, isLoading } = useQuery<OrgReport>({
    queryKey: ['calls.talkTime.org', from, to],
    queryFn: async () =>
      (await api.get('/calls/talk-time/org', {
        params: { from: `${from}T00:00:00.000Z`, to: `${to}T23:59:59.999Z` },
      })).data,
  });

  const employees = useMemo(() => data?.employees ?? [], [data?.employees]);
  const maxSeconds = useMemo(
    () => employees.reduce((m, e) => Math.max(m, e.totalSeconds), 0) || 1,
    [employees],
  );

  function exportCsv() {
    if (!employees.length) return;
    const header = ['Rank', 'Name', 'Designation', 'Total (s)', 'Total', 'Incoming (s)', 'Outgoing (s)', 'Calls', 'Missed'];
    const rows = employees.map((e) => [
      e.rank,
      e.name,
      e.customTitle || e.role,
      e.totalSeconds,
      fmtDuration(e.totalSeconds),
      e.incomingSeconds,
      e.outgoingSeconds,
      e.calls,
      e.missed,
    ]);
    const csv = [header, ...rows]
      .map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(','))
      .join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `talk-time_${from}_to_${to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="tt">
      <header className="tt__head">
        <div>
          <h1>Talk time</h1>
          <p>Call talk-time analytics across the organization.</p>
        </div>
        <div className="tt__filters">
          <label>
            From
            <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label>
            To
            <input type="date" value={to} min={from} max={isoDay(new Date())} onChange={(e) => setTo(e.target.value)} />
          </label>
          <button className="tt__export" onClick={exportCsv} disabled={!employees.length}>
            <Download size={15} /> Export CSV
          </button>
        </div>
      </header>

      <section className="tt__cards">
        <div className="tt__card">
          <div className="tt__card-icon tt__card-icon--brand"><Clock size={18} /></div>
          <div>
            <span className="tt__card-value">{isLoading ? '—' : fmtDuration(data?.totalCombinedSeconds ?? 0)}</span>
            <span className="tt__card-label">Total combined</span>
          </div>
        </div>
        <div className="tt__card">
          <div className="tt__card-icon tt__card-icon--info"><PhoneCall size={18} /></div>
          <div>
            <span className="tt__card-value">{isLoading ? '—' : fmtDuration(data?.averageSeconds ?? 0)}</span>
            <span className="tt__card-label">Avg / employee</span>
          </div>
        </div>
        <div className="tt__card">
          <div className="tt__card-icon tt__card-icon--success"><Users size={18} /></div>
          <div>
            <span className="tt__card-value">{isLoading ? '—' : data?.employeeCount ?? 0}</span>
            <span className="tt__card-label">Employees on calls</span>
          </div>
        </div>
      </section>

      <section className="tt__panel">
        <div className="tt__panel-head">
          <span>Employee ranking</span>
          <span className="tt__panel-sub">Ranked by total talk time</span>
        </div>
        {isLoading ? (
          <div className="tt__loading">
            {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} height={52} />)}
          </div>
        ) : !employees.length ? (
          <div className="tt__empty">No call activity in this date range.</div>
        ) : (
          <div className="tt__list">
            {employees.map((e) => (
              <article key={e.userId} className="tt__row">
                <span className="tt__rank">{e.rank}</span>
                <Avatar name={e.name} src={e.avatarUrl} size={36} />
                <div className="tt__who">
                  <UserName name={e.name} role={e.role} />
                  <span className="tt__title">{e.customTitle || e.role.replace(/_/g, ' ')}</span>
                </div>
                <div className="tt__bar-wrap">
                  <div className="tt__bar" style={{ width: `${(e.totalSeconds / maxSeconds) * 100}%` }} />
                </div>
                <div className="tt__metrics">
                  <span className="tt__total">{fmtDuration(e.totalSeconds)}</span>
                  <span className="tt__split">
                    <PhoneIncoming size={12} /> {fmtDuration(e.incomingSeconds)}
                    <PhoneOutgoing size={12} /> {fmtDuration(e.outgoingSeconds)}
                  </span>
                  <span className="tt__calls">{e.calls} calls{e.missed ? ` · ${e.missed} missed` : ''}</span>
                </div>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
