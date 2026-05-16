import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Monitor, Smartphone, X, Shield } from 'lucide-react';
import dayjs from 'dayjs';
import clsx from 'clsx';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Skeleton } from '@/components/ui/Skeleton';
import { toast } from '@/components/Toast';
import './sessions.css';

type Session = {
  id: string;
  status: string;
  ip: string | null;
  userAgent: string | null;
  device: string | null;
  platform: string | null;
  riskScore: number;
  firstSeenAt: string;
  lastSeenAt: string;
};

export default function SessionsPage() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery<{ items: Session[] }>({
    queryKey: ['sessions.mine'],
    queryFn: async () => (await api.get('/sessions/mine')).data,
    refetchInterval: 30_000,
  });

  const revokeMut = useMutation({
    mutationFn: async (id: string) => (await api.delete(`/sessions/${id}`)).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['sessions.mine'] }),
  });

  const revokeAllMut = useMutation({
    mutationFn: async () => (await api.post(`/sessions/mine/sign-out-everywhere`)).data,
    onSuccess: () => {
      toast.success('Signed out of all other devices');
      qc.invalidateQueries({ queryKey: ['sessions.mine'] });
    },
  });

  return (
    <div className="ss">
      <header className="ss__head">
        <div>
          <h1>Sessions</h1>
          <p>Devices that are currently signed in to your account.</p>
        </div>
        <Button variant="secondary" onClick={() => revokeAllMut.mutate()}>
          <Shield size={14} /> Sign out everywhere else
        </Button>
      </header>

      <div className="ss__list">
        {isLoading && Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} height={68} />)}
        {!isLoading && data?.items.map((s) => (
          <article key={s.id} className={clsx('ss__row', s.status !== 'ACTIVE' && 'is-inactive')}>
            <div className="ss__icon">
              {s.platform === 'android' || s.platform === 'ios' ? <Smartphone size={20} /> : <Monitor size={20} />}
            </div>
            <div className="ss__body">
              <div className="ss__title">
                {s.device || s.userAgent?.slice(0, 80) || 'Unknown device'}
                {s.riskScore >= 30 && <span className="ss__risk">Risk {s.riskScore}</span>}
              </div>
              <div className="ss__meta">
                {s.platform || 'web'} · {s.ip || 'unknown ip'} ·{' '}
                last seen {dayjs(s.lastSeenAt).format('MMM D, HH:mm')}
              </div>
            </div>
            <div className="ss__status">{s.status}</div>
            {s.status === 'ACTIVE' && (
              <button className="ss__revoke" onClick={() => revokeMut.mutate(s.id)} title="Revoke session">
                <X size={14} />
              </button>
            )}
          </article>
        ))}
        {!isLoading && (data?.items.length ?? 0) === 0 && <div className="ss__empty">No active sessions.</div>}
      </div>
    </div>
  );
}
