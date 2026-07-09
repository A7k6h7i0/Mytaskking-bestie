import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { LogIn, Download, Monitor, Smartphone, Laptop, Globe } from 'lucide-react';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Skeleton } from '@/components/ui/Skeleton';
import { SessionSelfieThumb } from '@/components/SessionSelfieThumb';
import './login-activity.css';

type ActivityRow = {
  id: string;
  user: { id: string; name: string; role?: string; avatarUrl?: string | null; customTitle?: string | null };
  status: 'ACTIVE' | 'REVOKED' | string;
  loginAt: string;
  lastSeenAt: string;
  logoutAt: string | null;
  device: string | null;
  platform: string | null;
  ip: string | null;
  city: string | null;
  country: string | null;
  selfieUrl?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  address?: string | null;
};

type ActivityResp = { total: number; page: number; pageSize: number; items: ActivityRow[] };

function isoDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function platformIcon(p: string | null) {
  switch ((p || '').toLowerCase()) {
    case 'android':
    case 'ios':
      return <Smartphone size={14} />;
    case 'windows':
    case 'macos':
    case 'linux':
      return <Laptop size={14} />;
    case 'web':
      return <Globe size={14} />;
    default:
      return <Monitor size={14} />;
  }
}

function sessionDuration(r: ActivityRow): string {
  const end = r.logoutAt ? dayjs(r.logoutAt) : dayjs();
  const mins = Math.max(0, end.diff(dayjs(r.loginAt), 'minute'));
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return `${h}h ${m}m`;
}

export default function LoginActivityPage() {
  const canViewEvidence = useAuthStore((s) => ['SUPER_ADMIN', 'ADMIN'].includes(s.user?.role || ''));
  const [from, setFrom] = useState(() => isoDay(new Date(Date.now() - 6 * 86400000)));
  const [to, setTo] = useState(() => isoDay(new Date()));

  const { data, isLoading } = useQuery<ActivityResp>({
    queryKey: ['sessions.activity', from, to],
    queryFn: async () =>
      (await api.get('/sessions/activity', {
        params: { from: `${from}T00:00:00.000Z`, to: `${to}T23:59:59.999Z`, pageSize: 100 },
      })).data,
  });

  const items = useMemo(() => data?.items ?? [], [data?.items]);

  function exportCsv() {
    if (!items.length) return;
    const header = ['Name', 'Designation', 'Login', 'Logout', 'Duration', 'Status', 'Platform', 'Device', 'IP'];
    if (canViewEvidence) header.push('Location', 'Latitude', 'Longitude', 'Selfie');
    const rows = items.map((r) => [
      r.user.name,
      r.user.customTitle || r.user.role || '',
      dayjs(r.loginAt).format('YYYY-MM-DD HH:mm:ss'),
      r.logoutAt ? dayjs(r.logoutAt).format('YYYY-MM-DD HH:mm:ss') : 'Active',
      sessionDuration(r),
      r.status,
      r.platform || '',
      r.device || '',
      r.ip || '',
      ...(canViewEvidence ? [r.address || '', r.latitude ?? '', r.longitude ?? '', r.selfieUrl || ''] : []),
    ]);
    const csv = [header, ...rows]
      .map((row) => row.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(','))
      .join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `login-activity_${from}_to_${to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="la">
      <header className="la__head">
        <div>
          <h1>Login activity</h1>
          <p>Login and logout history across the organization.</p>
        </div>
        <div className="la__filters">
          <label>
            From
            <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label>
            To
            <input type="date" value={to} min={from} max={isoDay(new Date())} onChange={(e) => setTo(e.target.value)} />
          </label>
          <button className="la__export" onClick={exportCsv} disabled={!items.length}>
            <Download size={15} /> Export CSV
          </button>
        </div>
      </header>

      <section className="la__panel">
        <div className="la__panel-head">
          <span><LogIn size={15} /> Sessions</span>
          <span className="la__panel-sub">{data ? `${data.total} total` : ''}</span>
        </div>
        {isLoading ? (
          <div className="la__loading">
            {Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} height={48} />)}
          </div>
        ) : !items.length ? (
          <div className="la__empty">No login activity in this date range.</div>
        ) : (
          <div className={`la__table${canViewEvidence ? ' la__table--evidence' : ''}`}>
            <div className="la__row la__row--head">
              <span>User</span><span>Login</span><span>Logout</span><span>Duration</span><span>Device</span><span>IP</span>
              {canViewEvidence && <><span>Location</span><span>Selfie</span></>}
            </div>
            {items.map((r) => (
              <div key={r.id} className="la__row">
                <span className="la__user">
                  <Avatar name={r.user.name} src={r.user.avatarUrl} size={30} />
                  <UserName name={r.user.name} role={r.user.role} />
                </span>
                <span className="la__time">{dayjs(r.loginAt).format('MMM D, HH:mm')}</span>
                <span className="la__time">
                  {r.logoutAt
                    ? dayjs(r.logoutAt).format('MMM D, HH:mm')
                    : <span className="la__active">Active now</span>}
                </span>
                <span className="la__dur">{sessionDuration(r)}</span>
                <span className="la__device">{platformIcon(r.platform)} {r.device || r.platform || '—'}</span>
                <span className="la__ip">{r.ip || '—'}</span>
                {canViewEvidence && (
                  <span className="la__location" title={r.address || undefined}>
                    {r.address || (r.latitude != null && r.longitude != null ? `${r.latitude.toFixed(5)}, ${r.longitude.toFixed(5)}` : 'Not captured')}
                  </span>
                )}
                {canViewEvidence && (
                  <span className="la__selfie">
                    {r.selfieUrl ? (
                      <SessionSelfieThumb sessionId={r.id} userName={r.user.name} />
                    ) : (
                      <span className="la__none">Not captured</span>
                    )}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
