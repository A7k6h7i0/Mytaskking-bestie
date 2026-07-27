import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useMemo, useState } from 'react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { toast } from '@/components/Toast';
import { useAuthStore } from '@/store/auth';
import './support-tickets.css';

type Ticket = {
  id: string;
  ticketNumber: string;
  issueTypeLabel?: string;
  description: string;
  status: string;
  statusLabel?: string;
  resolutionNotes?: string | null;
  reporter?: { name?: string; email?: string; userId?: string };
  assignee?: { id?: string; name?: string; email?: string } | null;
  assigneeId?: string | null;
};

type Assignee = {
  id: string;
  name: string;
  email?: string;
  tenant?: { name?: string };
};

export default function SupportIssuesPage() {
  const user = useAuthStore((s) => s.user)!;
  const isSuper = user.role === 'SUPER_ADMIN';
  const qc = useQueryClient();
  const [assignQuery, setAssignQuery] = useState('');
  const [assignTicketId, setAssignTicketId] = useState<string | null>(null);
  const [statusTicket, setStatusTicket] = useState<Ticket | null>(null);
  const [nextStatus, setNextStatus] = useState('IN_PROGRESS');
  const [resolutionNotes, setResolutionNotes] = useState('');

  const { data: meta } = useQuery({
    queryKey: ['support-tickets.meta'],
    queryFn: async () => (await api.get('/support-tickets/meta')).data,
  });

  const { data, isLoading } = useQuery<{ items: Ticket[] }>({
    queryKey: ['support-tickets.list', isSuper ? 'admin' : 'assigned'],
    queryFn: async () =>
      (await api.get(isSuper ? '/support-tickets/admin' : '/support-tickets/assigned')).data,
  });

  const { data: assignees } = useQuery<{ items: Assignee[] }>({
    queryKey: ['support-tickets.assignees', assignQuery],
    queryFn: async () =>
      (await api.get('/support-tickets/assignees', { params: { q: assignQuery } })).data,
    enabled: isSuper && assignTicketId != null,
  });

  const assignMut = useMutation({
    mutationFn: async ({ ticketId, assigneeId }: { ticketId: string; assigneeId: string }) =>
      (await api.patch(`/support-tickets/${ticketId}/assign`, { assigneeId })).data,
    onSuccess: () => {
      toast.success('Issue assigned');
      setAssignTicketId(null);
      qc.invalidateQueries({ queryKey: ['support-tickets.list'] });
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not assign issue'),
  });

  const statusMut = useMutation({
    mutationFn: async () =>
      (await api.patch(`/support-tickets/${statusTicket!.id}/status`, {
        status: nextStatus,
        resolutionNotes: resolutionNotes.trim() || undefined,
      })).data,
    onSuccess: () => {
      toast.success('Status updated');
      setStatusTicket(null);
      qc.invalidateQueries({ queryKey: ['support-tickets.list'] });
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not update status'),
  });

  const items = data?.items ?? [];
  const statuses = meta?.statuses ?? [];

  const title = useMemo(() => (isSuper ? 'Support inbox' : 'Issues'), [isSuper]);

  return (
    <div className="stt">
      <header className="stt__head">
        <div>
          <h1>{title}</h1>
          <p>
            {isSuper
              ? 'Review reported problems and assign one employee to each issue.'
              : 'Support issues assigned to you.'}
          </p>
        </div>
      </header>

      {isLoading ? (
        <p className="stt__subtle">Loading…</p>
      ) : items.length === 0 ? (
        <p className="stt__subtle">{isSuper ? 'No support tickets yet.' : 'No assigned issues.'}</p>
      ) : (
        <div className="stt__list">
          {items.map((t) => (
            <article key={t.id} className="stt__item">
              <div className="stt__ticket-head">
                <strong>{t.ticketNumber}</strong>
                <span className={`stt__badge stt__badge--${t.status.toLowerCase()}`}>
                  {t.statusLabel || t.status}
                </span>
              </div>
              <p>{t.issueTypeLabel}</p>
              {isSuper && t.reporter && (
                <p className="stt__subtle">
                  From {t.reporter.name} ({t.reporter.email || t.reporter.userId})
                </p>
              )}
              {t.assignee?.name && (
                <p className="stt__subtle">Assignee: {t.assignee.name}</p>
              )}
              <p className="stt__desc">{t.description}</p>
              <div className="stt__actions">
                {isSuper && (
                  <Button variant="secondary" onClick={() => setAssignTicketId(t.id)}>
                    Assign
                  </Button>
                )}
                {(isSuper || t.assigneeId === user.id) && (
                  <Button
                    variant="secondary"
                    onClick={() => {
                      setStatusTicket(t);
                      setNextStatus(t.status === 'ASSIGNED' ? 'IN_PROGRESS' : t.status);
                      setResolutionNotes(t.resolutionNotes || '');
                    }}
                  >
                    Update status
                  </Button>
                )}
              </div>
            </article>
          ))}
        </div>
      )}

      {assignTicketId && (
        <div className="stt__modal-backdrop" onClick={() => setAssignTicketId(null)}>
          <div className="stt__modal" onClick={(e) => e.stopPropagation()}>
            <h2>Assign employee</h2>
            <Input
              label="Search"
              value={assignQuery}
              onChange={(e) => setAssignQuery(e.target.value)}
              placeholder="Name or email"
            />
            <div className="stt__assignee-list">
              {(assignees?.items ?? []).map((u) => (
                <button
                  key={u.id}
                  type="button"
                  className="stt__assignee"
                  onClick={() => assignMut.mutate({ ticketId: assignTicketId, assigneeId: u.id })}
                >
                  <strong>{u.name}</strong>
                  <span>{[u.email, u.tenant?.name].filter(Boolean).join(' · ')}</span>
                </button>
              ))}
            </div>
            <Button variant="secondary" onClick={() => setAssignTicketId(null)}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {statusTicket && (
        <div className="stt__modal-backdrop" onClick={() => setStatusTicket(null)}>
          <div className="stt__modal" onClick={(e) => e.stopPropagation()}>
            <h2>{statusTicket.ticketNumber}</h2>
            <label className="stt__label">
              Status
              <select
                className="stt__select"
                value={nextStatus}
                onChange={(e) => setNextStatus(e.target.value)}
              >
                {statuses.map((s: { value: string; label: string }) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="stt__label">
              Resolution notes
              <textarea
                className="stt__textarea"
                rows={4}
                value={resolutionNotes}
                onChange={(e) => setResolutionNotes(e.target.value)}
              />
            </label>
            <div className="stt__actions">
              <Button onClick={() => statusMut.mutate()} loading={statusMut.isPending}>
                Save
              </Button>
              <Button variant="secondary" onClick={() => setStatusTicket(null)}>
                Cancel
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
