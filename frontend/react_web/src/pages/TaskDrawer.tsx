import { useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Check, X, CheckCircle2, Sparkles, Clock, AlertTriangle } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { Drawer } from '@/components/ui/Drawer';
import { Button } from '@/components/ui/Button';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Badge } from '@/components/ui/Badge';
import { ProgressRing } from '@/components/ui/Progress';
import { SuccessCheck } from '@/components/ui/SuccessCheck';
import { RiveSlot, type RiveSlotName } from '@/components/ui/RiveSlot';
import { toast } from '@/components/Toast';
import './task-drawer.css';

interface Props {
  taskId: string | null;
  onClose: () => void;
}

type AssigneeRow = {
  user: { id: string; name: string; avatarUrl?: string | null; isClient: boolean; role: string };
  state: 'PENDING' | 'ACCEPTED' | 'DECLINED' | 'COMPLETED';
  acceptedAt?: string | null;
  completedAt?: string | null;
  score?: number | null;
  scoreReason?: string | null;
};

type TaskDetail = {
  id: string; title: string; description?: string | null;
  status: string; priority: string; dueAt?: string | null;
  createdById: string;
  createdBy?: { id: string; name: string; avatarUrl?: string | null; isClient: boolean; role: string };
  assignees: AssigneeRow[];
};

/**
 * Side panel that drives the full assignee lifecycle for one task:
 * PENDING → Accept | Decline → COMPLETED (with score).
 *
 * Mounted at app level — opens whenever the parent component sets `taskId`.
 * On close we drop the query so the next open refetches fresh state.
 */
export function TaskDrawer({ taskId, onClose }: Props) {
  const qc = useQueryClient();
  const me = useAuthStore((s) => s.user);

  const { data, isLoading } = useQuery<TaskDetail>({
    queryKey: ['task.detail', taskId],
    queryFn: async () => (await api.get(`/tasks/${taskId}`)).data,
    enabled: !!taskId,
  });

  const myAssignment = useMemo<AssigneeRow | undefined>(
    () => data?.assignees.find((a) => a.user.id === me?.id),
    [data, me]
  );

  function invalidate() {
    qc.invalidateQueries({ queryKey: ['tasks.kanban'] });
    qc.invalidateQueries({ queryKey: ['task.detail', taskId] });
    qc.invalidateQueries({ queryKey: ['notifications.grouped'] });
  }

  const accept = useMutation({
    mutationFn: async () => (await api.post(`/tasks/${taskId}/accept`)).data,
    onSuccess: () => { toast.success('Accepted'); invalidate(); },
    onError: () => toast.error('Could not accept'),
  });
  const decline = useMutation({
    mutationFn: async () => (await api.post(`/tasks/${taskId}/decline`)).data,
    onSuccess: () => { toast.info('Declined', 'The creator was notified.'); invalidate(); },
    onError: () => toast.error('Could not decline'),
  });
  const complete = useMutation({
    mutationFn: async () => (await api.post(`/tasks/${taskId}/complete`)).data,
    onSuccess: (row: AssigneeRow & { autoCompleted?: boolean }) => {
      toast.success(`Completed · ${row.score}/100`, row.scoreReason || undefined);
      invalidate();
    },
    onError: () => toast.error('Could not complete'),
  });

  if (!taskId) return null;

  return (
    <Drawer
      open
      onClose={onClose}
      side="right"
      width={460}
      title={data?.title || 'Loading…'}
      footer={
        myAssignment ? (
          <TaskFooter
            assignment={myAssignment}
            onAccept={() => accept.mutate()}
            onDecline={() => decline.mutate()}
            onComplete={() => complete.mutate()}
            busy={accept.isPending || decline.isPending || complete.isPending}
          />
        ) : null
      }
    >
      {isLoading || !data ? (
        <div className="td__loading">Loading…</div>
      ) : (
        <div className="td">
          {/* ---- meta strip ---- */}
          <div className="td__meta">
            <Badge tone={priorityTone(data.priority)} variant="soft">{data.priority}</Badge>
            <Badge tone={statusTone(data.status)}>{data.status.replace('_', ' ')}</Badge>
            {data.dueAt && (
              <span className="td__due">
                <Clock size={12} /> Due {dayjs(data.dueAt).format('MMM D, HH:mm')}
                <span className="td__due-rel">{relative(data.dueAt)}</span>
              </span>
            )}
          </div>

          {data.description && <p className="td__desc">{data.description}</p>}

          {/* ---- creator ---- */}
          {data.createdBy && (
            <section className="td__section">
              <h4>Created by</h4>
              <div className="td__person">
                <Avatar name={data.createdBy.name} src={data.createdBy.avatarUrl} isClient={data.createdBy.isClient} size={28} />
                <UserName name={data.createdBy.name} isClient={data.createdBy.isClient} role={data.createdBy.role} />
              </div>
            </section>
          )}

          {/* ---- assignees + their states ---- */}
          <section className="td__section">
            <h4>Assignees</h4>
            {data.assignees.length === 0 && <div className="td__hint">No one is assigned yet.</div>}
            <ul className="td__assignees">
              {data.assignees.map((a) => (
                <li key={a.user.id} className={`td__assignee td__assignee--${a.state.toLowerCase()}`}>
                  <Avatar name={a.user.name} src={a.user.avatarUrl} isClient={a.user.isClient} size={32} />
                  <div className="td__assignee-body">
                    <div className="td__assignee-name">
                      <UserName name={a.user.name} isClient={a.user.isClient} role={a.user.role} />
                      <StateBadge state={a.state} />
                    </div>
                    {a.state === 'COMPLETED' && (
                      <div className="td__assignee-meta">
                        Completed {dayjs(a.completedAt).fromNow?.() || dayjs(a.completedAt).format('MMM D')}
                        {a.scoreReason && ` · ${a.scoreReason}`}
                      </div>
                    )}
                    {a.state === 'ACCEPTED' && a.acceptedAt && (
                      <div className="td__assignee-meta">
                        Accepted {dayjs(a.acceptedAt).fromNow?.() || dayjs(a.acceptedAt).format('MMM D')}
                      </div>
                    )}
                  </div>
                  {a.state === 'COMPLETED' && typeof a.score === 'number' && (
                    <ProgressRing
                      value={a.score}
                      size={42}
                      thickness={4}
                      tone={a.score >= 80 ? 'success' : a.score >= 50 ? 'warning' : 'danger'}
                      label={<strong>{a.score}</strong>}
                    />
                  )}
                </li>
              ))}
            </ul>
          </section>

          {/* ---- celebration if I completed it ---- */}
          {myAssignment?.state === 'COMPLETED' && (
            <section className="td__celebrate m-pop">
              <RiveSlot name={scoreRive(myAssignment.score)} size={88}
                fallback={<SuccessCheck size={56} />} />
              <div>
                <strong>Nice work — {myAssignment.score}/100</strong>
                <p>{myAssignment.scoreReason}</p>
              </div>
            </section>
          )}
        </div>
      )}
    </Drawer>
  );
}

function TaskFooter({
  assignment, onAccept, onDecline, onComplete, busy,
}: {
  assignment: AssigneeRow;
  onAccept: () => void;
  onDecline: () => void;
  onComplete: () => void;
  busy: boolean;
}) {
  switch (assignment.state) {
    case 'PENDING':
      return (
        <>
          <Button variant="ghost" onClick={onDecline} disabled={busy}>
            <X size={14} /> Decline
          </Button>
          <Button onClick={onAccept} loading={busy}>
            <Check size={14} /> Accept task
          </Button>
        </>
      );
    case 'ACCEPTED':
      return (
        <>
          <span className="td__footer-note">
            <AlertTriangle size={12} /> Once you mark complete, your score is locked.
          </span>
          <Button onClick={onComplete} loading={busy} className="m-press">
            <CheckCircle2 size={14} /> Mark complete
          </Button>
        </>
      );
    case 'DECLINED':
      return <span className="td__footer-note">You declined this task.</span>;
    case 'COMPLETED':
      return (
        <span className="td__footer-note td__footer-note--success">
          <Sparkles size={12} /> Completed · {assignment.score}/100
        </span>
      );
    default:
      return null;
  }
}

function StateBadge({ state }: { state: AssigneeRow['state'] }) {
  const map: Record<AssigneeRow['state'], { tone: 'brand' | 'warning' | 'success' | 'danger' | 'neutral'; label: string }> = {
    PENDING:   { tone: 'warning', label: 'Awaiting accept' },
    ACCEPTED:  { tone: 'brand',   label: 'Accepted' },
    DECLINED:  { tone: 'danger',  label: 'Declined' },
    COMPLETED: { tone: 'success', label: 'Completed' },
  };
  const { tone, label } = map[state];
  return <Badge tone={tone} dot>{label}</Badge>;
}

function priorityTone(p: string): 'neutral' | 'info' | 'warning' | 'danger' {
  if (p === 'URGENT') return 'danger';
  if (p === 'HIGH') return 'warning';
  if (p === 'MEDIUM') return 'info';
  return 'neutral';
}
function statusTone(s: string): 'neutral' | 'brand' | 'info' | 'warning' | 'success' {
  if (s === 'DONE') return 'success';
  if (s === 'IN_PROGRESS') return 'info';
  if (s === 'REVIEW') return 'warning';
  if (s === 'TODO' || s === 'BACKLOG') return 'brand';
  return 'neutral';
}
function scoreRive(score?: number | null): RiveSlotName {
  if (score == null) return 'task.completed';
  if (score >= 95) return 'score.perfect';
  if (score >= 80) return 'score.great';
  if (score >= 60) return 'score.good';
  return 'score.late';
}

function relative(iso: string): string {
  const diff = new Date(iso).getTime() - Date.now();
  const h = diff / 3_600_000;
  if (Math.abs(h) < 1) return ` · ${Math.round(h * 60)}m`;
  if (Math.abs(h) < 24) return ` · ${h > 0 ? '+' : ''}${Math.round(h)}h`;
  return ` · ${Math.round(h / 24)}d`;
}
