import { useQuery } from '@tanstack/react-query';
import { Activity, CheckCircle2, MessageCircle, Phone, UserCog, Users, type LucideIcon } from 'lucide-react';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { UserName } from '@/components/ui/UserName';
import { DashboardWidgets } from '@/components/DashboardWidgets';
import { AnimatedNumber } from '@/components/ui/AnimatedNumber';
import { TiltCard } from '@/components/ui/TiltCard';
import { ScrollReveal } from '@/components/effects/ScrollReveal';
import './dashboard.css';

type Overview = {
  counts: Record<string, number | string | null>;
  recentActivity?: any[];
  channels?: any[];
};

export default function DashboardPage() {
  const user = useAuthStore((s) => s.user)!;
  const { data, isLoading } = useQuery<Overview>({
    queryKey: ['dashboard.overview'],
    queryFn: async () => (await api.get('/dashboard/overview')).data,
  });

  if (isLoading || !data) return <div className="db__loading">Loading workspace…</div>;

  const isAdmin = user.role === 'SUPER_ADMIN' || user.role === 'ADMIN';
  const isClient = user.isClient;

  return (
    <div className="db">
      <header className="db__head">
        <div>
          <h1 className="db__title">
            {isClient ? `Hello, ` : `Welcome back, `}
            <UserName name={user.name.split(' ')[0]} isClient={user.isClient} role={user.role} />
          </h1>
          <p className="db__sub">
            {isAdmin
              ? 'A snapshot of your organization in realtime.'
              : isClient
              ? 'Your collaboration workspace.'
              : 'Your assignments, channels and activity.'}
          </p>
        </div>
      </header>

      <section className="db__grid">
        {isAdmin && (
          <>
            <Stat icon={Users} label="Employees" value={data.counts.employees} accent="brand" />
            <Stat icon={UserCog} label="Clients" value={data.counts.clients} accent="client" />
            <Stat icon={CheckCircle2} label="Tasks open" value={data.counts.tasksOpen} accent="warning" />
            <Stat icon={Activity} label="Tasks done · 7d" value={data.counts.tasksDoneThisWeek} accent="success" />
            <Stat icon={Phone} label="Calls today" value={data.counts.callsToday} accent="info" />
            <Stat icon={MessageCircle} label="Active calls" value={data.counts.activeCalls} accent="brand" />
          </>
        )}
        {!isAdmin && !isClient && (
          <>
            <Stat icon={CheckCircle2} label="Open tasks" value={data.counts.myOpenTasks} accent="warning" />
            <Stat icon={Activity} label="Done this week" value={data.counts.myDoneThisWeek} accent="success" />
            <Stat icon={MessageCircle} label="Channels" value={data.counts.activeChannels} accent="brand" />
            <Stat icon={Phone} label="Unread alerts" value={data.counts.unreadNotifs} accent="info" />
          </>
        )}
        {isClient && (
          <>
            <Stat icon={MessageCircle} label="Channels" value={data.counts.channels} accent="brand" />
            <Stat icon={Activity} label="Unread" value={data.counts.unreadNotifs} accent="warning" />
            <Stat
              icon={UserCog}
              label="Access until"
              value={data.counts.accessEndsAt ? new Date(String(data.counts.accessEndsAt)).toLocaleDateString() : '—'}
              accent="client"
            />
          </>
        )}
      </section>

      <DashboardWidgets />

      {isAdmin && data.recentActivity && (
        <ScrollReveal variant="up">
        <section className="db__activity">
          <div className="db__card-head">
            <h3>Recent activity</h3>
            <span className="db__hint">Realtime</span>
          </div>
          <ul className="db__activity-list">
            {data.recentActivity.length === 0 && (
              <li className="db__empty">Quiet so far. Activity will appear here as it happens.</li>
            )}
            {data.recentActivity.map((a) => (
              <li key={a.id}>
                <span className="db__activity-dot" />
                <UserName name={a.actor?.name || 'System'} isClient={a.actor?.isClient} role={a.actor?.role} />
                <span className="db__activity-kind">{a.kind}</span>
                <span className="db__activity-time">{new Date(a.createdAt).toLocaleTimeString()}</span>
              </li>
            ))}
          </ul>
        </section>
        </ScrollReveal>
      )}
    </div>
  );
}

function Stat({
  icon: Icon,
  label,
  value,
  accent,
}: {
  icon: LucideIcon;
  label: string;
  value: number | string | null | undefined;
  accent: 'brand' | 'success' | 'warning' | 'info' | 'client';
}) {
  const isNumeric = typeof value === 'number';
  return (
    <TiltCard max={6} glow className={`db__stat db__stat--${accent}`}>
      <div className="db__stat-icon m-tilt-layer-1 m-pop"><Icon size={18} /></div>
      <div className="db__stat-body m-tilt-layer-2">
        <div className="db__stat-label">{label}</div>
        <div className="db__stat-value">
          {isNumeric
            ? <AnimatedNumber value={value as number} />
            : (value ?? 0)}
        </div>
      </div>
    </TiltCard>
  );
}
