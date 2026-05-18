import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, GripVertical, Calendar, Users, X, Clock } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Modal } from '@/components/ui/Modal';
import { Badge } from '@/components/ui/Badge';
import { useAuthStore } from '@/store/auth';
import { getSocket } from '@/services/socket';
import { toast } from '@/components/Toast';
import { TaskDrawer } from '@/pages/TaskDrawer';
import './tasks.css';

const COLUMNS: Array<{ key: string; label: string }> = [
  { key: 'BACKLOG', label: 'Backlog' },
  { key: 'TODO', label: 'To do' },
  { key: 'IN_PROGRESS', label: 'In progress' },
  { key: 'REVIEW', label: 'Review' },
  { key: 'DONE', label: 'Done' },
];

const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'URGENT'] as const;
type Priority = (typeof PRIORITIES)[number];

type Task = {
  id: string; title: string; description?: string | null;
  status: string; priority: string; dueAt?: string | null;
  assignees: { user: Person; state?: AssignmentState; score?: number | null }[];
};
type Person = { id: string; userId: string; name: string; avatarUrl?: string | null; isClient: boolean; role: string };
type AssignmentState = 'PENDING' | 'ACCEPTED' | 'DECLINED' | 'COMPLETED';

export default function TasksPage() {
  const qc = useQueryClient();
  const me = useAuthStore((s) => s.user);
  const [creating, setCreating] = useState(false);
  const [openTaskId, setOpenTaskId] = useState<string | null>(null);

  const { data, isLoading } = useQuery<{ view: 'kanban'; columns: Record<string, Task[]> }>({
    queryKey: ['tasks.kanban'],
    queryFn: async () => (await api.get('/tasks', { params: { view: 'kanban' } })).data,
  });

  const moveMut = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) =>
      (await api.post(`/tasks/${id}/move`, { status })).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks.kanban'] }),
  });

  // Listen for `task.assigned` events — pop a toast the moment someone
  // assigns a task to me, even before the notification feed refetches.
  useEffect(() => {
    const s = getSocket();
    if (!s || !me) return;
    const onAssigned = (p: { task: Task; assignerId: string; assignerName: string }) => {
      const mine = p.task.assignees?.some((a) => a.user.id === me.id);
      if (!mine) return;
      const due = p.task.dueAt ? `· due ${dayjs(p.task.dueAt).format('MMM D, HH:mm')}` : '';
      toast.info(`${p.assignerName} assigned you a task`, `${p.task.title} ${due}`);
      qc.invalidateQueries({ queryKey: ['tasks.kanban'] });
      qc.invalidateQueries({ queryKey: ['notifications.grouped'] });
    };
    const onAssignmentChanged = () => {
      qc.invalidateQueries({ queryKey: ['tasks.kanban'] });
      qc.invalidateQueries({ queryKey: ['task.detail'] });
    };
    s.on('task.assigned', onAssigned);
    s.on('task.created', () => qc.invalidateQueries({ queryKey: ['tasks.kanban'] }));
    s.on('task.moved',   () => qc.invalidateQueries({ queryKey: ['tasks.kanban'] }));
    s.on('task.assignment.changed', onAssignmentChanged);
    return () => {
      s.off('task.assigned', onAssigned);
      s.off('task.assignment.changed', onAssignmentChanged);
    };
  }, [me, qc]);

  function onDragStart(e: React.DragEvent, taskId: string) {
    e.dataTransfer.setData('text/plain', taskId);
  }
  function onDrop(e: React.DragEvent, status: string) {
    e.preventDefault();
    const id = e.dataTransfer.getData('text/plain');
    if (id) moveMut.mutate({ id, status });
  }

  return (
    <div className="tk">
      <header className="tk__head">
        <div>
          <h1 className="tk__title">Tasks</h1>
          <p className="tk__sub">Realtime kanban — drag cards to update status. Anyone can assign to anyone.</p>
        </div>
        <Button onClick={() => setCreating(true)} className="m-press"><Plus size={16}/> New task</Button>
      </header>

      <div className="tk__board">
        {COLUMNS.map((col) => (
          <div
            key={col.key}
            className="tk__col"
            onDragOver={(e) => e.preventDefault()}
            onDrop={(e) => onDrop(e, col.key)}
          >
            <div className="tk__col-head">
              <span>{col.label}</span>
              <span className="tk__col-count">{data?.columns?.[col.key]?.length ?? 0}</span>
            </div>
            <div className="tk__col-body">
              {(data?.columns?.[col.key] || []).map((t) => {
                const mine = t.assignees.find((a) => a.user.id === me?.id);
                return (
                  <article
                    key={t.id}
                    draggable
                    onDragStart={(e) => onDragStart(e, t.id)}
                    onClick={() => setOpenTaskId(t.id)}
                    className={`tk__card tk__card--${t.priority.toLowerCase()}${mine?.state ? ` tk__card--${mine.state.toLowerCase()}` : ''}`}
                  >
                    <div className="tk__card-head">
                      <GripVertical size={14} className="tk__drag" />
                      <span className="tk__card-title">{t.title}</span>
                    </div>

                    {/* my own state on this task — only when I'm an assignee */}
                    {mine && (
                      <div className="tk__card-state">
                        {mine.state === 'PENDING' && (
                          <Badge tone="warning" dot>Awaiting your accept</Badge>
                        )}
                        {mine.state === 'ACCEPTED' && (
                          <Badge tone="brand" dot>Accepted · ready to complete</Badge>
                        )}
                        {mine.state === 'COMPLETED' && typeof mine.score === 'number' && (
                          <Badge
                            tone={mine.score >= 80 ? 'success' : mine.score >= 50 ? 'warning' : 'danger'}
                            dot
                          >Completed · {mine.score}/100</Badge>
                        )}
                        {mine.state === 'DECLINED' && (
                          <Badge tone="danger" dot>You declined</Badge>
                        )}
                      </div>
                    )}

                    <div className="tk__card-foot">
                      <div className="tk__avatars">
                        {t.assignees.slice(0, 3).map((a) => (
                          <Avatar key={a.user.id} name={a.user.name} src={a.user.avatarUrl} isClient={a.user.isClient} size={22} />
                        ))}
                      </div>
                      {t.dueAt && (
                        <span className="tk__due"><Calendar size={12} /> {dayjs(t.dueAt).format('MMM D, HH:mm')}</span>
                      )}
                    </div>
                    {t.assignees[0] && (
                      <div className="tk__byline">
                        <UserName
                          name={t.assignees[0].user.name}
                          isClient={t.assignees[0].user.isClient}
                          role={t.assignees[0].user.role}
                        />
                      </div>
                    )}
                  </article>
                );
              })}
              {!isLoading && (data?.columns?.[col.key]?.length ?? 0) === 0 && (
                <div className="tk__col-empty">Drop here</div>
              )}
            </div>
          </div>
        ))}
      </div>

      <NewTaskModal open={creating} onClose={() => setCreating(false)} />
      <TaskDrawer taskId={openTaskId} onClose={() => setOpenTaskId(null)} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// New-task modal: title + description + priority + due date/time + assignees
// ─────────────────────────────────────────────────────────────────────────────

function NewTaskModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const qc = useQueryClient();
  const me = useAuthStore((s) => s.user);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState<Priority>('MEDIUM');
  const [dueDate, setDueDate] = useState<string>('');
  const [dueTime, setDueTime] = useState<string>('17:00');
  const [picked, setPicked] = useState<Person[]>([]);
  const [peopleQuery, setPeopleQuery] = useState('');

  // Reset whenever the dialog opens.
  useEffect(() => {
    if (open) {
      setTitle(''); setDescription(''); setPriority('MEDIUM');
      setDueDate(dayjs().add(1, 'day').format('YYYY-MM-DD'));
      setDueTime('17:00');
      setPicked([]);
      setPeopleQuery('');
    }
  }, [open]);

  // Pull employees + admins + telecallers — anyone the assigner could give work to.
  const { data: peopleData } = useQuery<{ items: Person[] }>({
    queryKey: ['people.assignable', peopleQuery],
    queryFn: async () => (await api.get('/employees', { params: { q: peopleQuery || undefined } })).data,
    enabled: open,
  });

  const candidates = useMemo(() => {
    const pool = peopleData?.items || [];
    const pickedIds = new Set(picked.map((p) => p.id));
    return pool.filter((p) => !pickedIds.has(p.id));
  }, [peopleData, picked]);

  const createMut = useMutation({
    mutationFn: async () => {
      const dueAt = dueDate ? new Date(`${dueDate}T${dueTime || '00:00'}`).toISOString() : undefined;
      const body = {
        title: title.trim(),
        description: description.trim() || undefined,
        priority,
        status: 'TODO',
        assigneeIds: picked.map((p) => p.id),
        ...(dueAt ? { dueAt } : {}),
      };
      return (await api.post('/tasks', body)).data;
    },
    onSuccess: (task) => {
      toast.success(
        picked.length === 0
          ? 'Task created'
          : `Assigned to ${picked.length} ${picked.length === 1 ? 'person' : 'people'}`,
        task.dueAt ? `Due ${dayjs(task.dueAt).format('MMM D, HH:mm')}` : undefined,
      );
      qc.invalidateQueries({ queryKey: ['tasks.kanban'] });
      onClose();
    },
    onError: () => toast.error('Could not create task'),
  });

  const canSubmit = title.trim().length > 0 && !createMut.isPending;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="New task"
      description="Assign to anyone in the workspace. Both you and the assignee get a notification + push."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={createMut.isPending}>Cancel</Button>
          <Button onClick={() => createMut.mutate()} loading={createMut.isPending} disabled={!canSubmit}>
            Create + notify
          </Button>
        </>
      }
    >
      <div className="tk__form">
        <Input label="Title" placeholder="What needs to happen?" autoFocus value={title} onChange={(e) => setTitle(e.target.value)} />

        <label className="tk__field">
          <span>Description (optional)</span>
          <textarea
            rows={3}
            placeholder="Anything the assignee should know"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
        </label>

        <div className="tk__row">
          <label className="tk__field">
            <span>Priority</span>
            <select value={priority} onChange={(e) => setPriority(e.target.value as Priority)}>
              {PRIORITIES.map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          </label>

          <Input
            label="Due date"
            type="date"
            leading={<Calendar size={14} />}
            value={dueDate}
            onChange={(e) => setDueDate(e.target.value)}
          />

          <Input
            label="Due time"
            type="time"
            leading={<Clock size={14} />}
            value={dueTime}
            onChange={(e) => setDueTime(e.target.value)}
          />
        </div>

        <div className="tk__field">
          <span className="tk__field-label">Assign to</span>
          {picked.length > 0 && (
            <div className="tk__chips">
              {picked.map((p) => (
                <button
                  key={p.id}
                  className="tk__chip"
                  onClick={() => setPicked((prev) => prev.filter((x) => x.id !== p.id))}
                >
                  <Avatar name={p.name} src={p.avatarUrl} isClient={p.isClient} size={18} />
                  <UserName name={p.name} isClient={p.isClient} role={p.role} />
                  <X size={12} />
                </button>
              ))}
            </div>
          )}
          <Input
            placeholder="Search people…"
            leading={<Users size={14} />}
            value={peopleQuery}
            onChange={(e) => setPeopleQuery(e.target.value)}
          />
          <div className="tk__people">
            {candidates.slice(0, 8).map((p) => (
              <button
                key={p.id}
                className="tk__person"
                onClick={() => { setPicked((prev) => [...prev, p]); setPeopleQuery(''); }}
              >
                <Avatar name={p.name} src={p.avatarUrl} isClient={p.isClient} size={26} />
                <div>
                  <UserName name={p.name} isClient={p.isClient} role={p.role} />
                  <span className="tk__person-meta">{p.userId} · {p.role.replace('_', ' ')}</span>
                </div>
                {p.id === me?.id && <Badge tone="neutral">You</Badge>}
              </button>
            ))}
            {candidates.length === 0 && <div className="tk__hint">No matching people.</div>}
          </div>
        </div>
      </div>
    </Modal>
  );
}
