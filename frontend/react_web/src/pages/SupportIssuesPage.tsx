import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useMemo, useState } from 'react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { toast } from '@/components/Toast';
import { useAuthStore } from '@/store/auth';
import {
  assigneeStatusOptions,
  defaultAssigneeStatus,
  isPlatformSuperAdmin,
} from '@/utils/supportAccess';
import './support-tickets.css';

type AssigneeUser = {
  id: string;
  name: string;
  email?: string;
  role?: string;
  userId?: string;
};

type Ticket = {
  id: string;
  ticketNumber: string;
  issueTypeLabel?: string;
  description: string;
  status: string;
  statusLabel?: string;
  resolutionNotes?: string | null;
  reporter?: { name?: string; email?: string; userId?: string };
  assignees?: AssigneeUser[];
  assigneeIds?: string[];
};

type AssigneeOption = {
  id: string;
  name: string;
  email?: string;
  tenant?: { name?: string };
};

function isClosed(status: string) {
  return status === 'CLOSED';
}

export default function SupportIssuesPage() {
  const user = useAuthStore((s) => s.user)!;
  const isSuper = isPlatformSuperAdmin(user);
  const qc = useQueryClient();
  const [assignQuery, setAssignQuery] = useState('');
  const [assignTicket, setAssignTicket] = useState<Ticket | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
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

  const { data: assignees } = useQuery<{ items: AssigneeOption[] }>({
    queryKey: ['support-tickets.assignees', assignQuery],
    queryFn: async () =>
      (await api.get('/support-tickets/assignees', { params: { q: assignQuery } })).data,
    enabled: isSuper && assignTicket != null,
  });

  useEffect(() => {
    if (!assignTicket) return;
    setSelectedIds(new Set(assignTicket.assigneeIds ?? []));
    setAssignQuery('');
  }, [assignTicket]);

  const assignMut = useMutation({
    mutationFn: async ({ ticketId, assigneeIds }: { ticketId: string; assigneeIds: string[] }) =>
      (await api.patch(`/support-tickets/${ticketId}/assign`, { assigneeIds })).data,
    onSuccess: () => {
      toast.success('Assignees updated');
      setAssignTicket(null);
      qc.invalidateQueries({ queryKey: ['support-tickets.list'] });
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not update assignees'),
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
  const selectableStatuses = isSuper ? statuses : assigneeStatusOptions(statuses);

  const title = useMemo(() => (isSuper ? 'Support inbox' : 'Issues'), [isSuper]);

  function toggleAssignee(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function userCanUpdate(t: Ticket) {
    if (isSuper) return true;
    if (isClosed(t.status)) return false;
    return (t.assigneeIds ?? []).includes(user.id);
  }

  function openStatusModal(t: Ticket) {
    setStatusTicket(t);
    setNextStatus(
      isSuper
        ? t.status === 'ASSIGNED'
          ? 'IN_PROGRESS'
          : t.status
        : defaultAssigneeStatus(t.status),
    );
    setResolutionNotes(t.resolutionNotes || '');
  }

  return (
    <div className="stt">
      <header className="stt__head">
        <div>
          <h1>{title}</h1>
          <p>
            {isSuper
              ? 'Review reported problems and assign platform team members to each issue.'
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
          {items.map((t) => {
            const closed = isClosed(t.status);
            const hasAssignees = (t.assigneeIds?.length ?? 0) > 0;
            return (
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
                {(t.assignees?.length ?? 0) > 0 && (
                  <p className="stt__subtle">
                    Assigned: {t.assignees!.map((a) => a.name).join(', ')}
                  </p>
                )}
                <p className="stt__desc">{t.description}</p>
                <div className="stt__actions">
                  {isSuper && (
                    <Button
                      variant="secondary"
                      disabled={closed}
                      title={closed ? 'Cannot assign on a closed ticket' : undefined}
                      onClick={() => setAssignTicket(t)}
                    >
                      {hasAssignees ? 'Edit assigns' : 'Assign employees'}
                    </Button>
                  )}
                  {userCanUpdate(t) && (
                    <Button
                      variant="secondary"
                      onClick={() => openStatusModal(t)}
                    >
                      Update status
                    </Button>
                  )}
                </div>
              </article>
            );
          })}
        </div>
      )}

      {assignTicket && (
        <div className="stt__modal-backdrop" onClick={() => setAssignTicket(null)}>
          <div className="stt__modal stt__modal--wide" onClick={(e) => e.stopPropagation()}>
            <h2>{(assignTicket.assigneeIds?.length ?? 0) > 0 ? 'Edit assigns' : 'Assign employees'}</h2>
            <p className="stt__subtle">Select one or more default-tenant employees. Unchecked people lose access to this issue.</p>
            <Input
              label="Search"
              value={assignQuery}
              onChange={(e) => setAssignQuery(e.target.value)}
              placeholder="Name or email"
            />
            <div className="stt__assignee-list stt__assignee-list--checks">
              {(assignees?.items ?? []).map((u) => (
                <label key={u.id} className="stt__assignee-check">
                  <input
                    type="checkbox"
                    checked={selectedIds.has(u.id)}
                    onChange={() => toggleAssignee(u.id)}
                  />
                  <span>
                    <strong>{u.name}</strong>
                    <span>{[u.email, u.tenant?.name].filter(Boolean).join(' · ')}</span>
                  </span>
                </label>
              ))}
            </div>
            <div className="stt__actions">
              <Button
                onClick={() =>
                  assignMut.mutate({
                    ticketId: assignTicket.id,
                    assigneeIds: [...selectedIds],
                  })
                }
                loading={assignMut.isPending}
              >
                Save assigns
              </Button>
              <Button variant="secondary" onClick={() => setAssignTicket(null)}>
                Cancel
              </Button>
            </div>
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
                {selectableStatuses.map((s: { value: string; label: string }) => (
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
