import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, GripVertical, Calendar } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Button } from '@/components/ui/Button';
import './tasks.css';

const COLUMNS: Array<{ key: string; label: string }> = [
  { key: 'BACKLOG', label: 'Backlog' },
  { key: 'TODO', label: 'To do' },
  { key: 'IN_PROGRESS', label: 'In progress' },
  { key: 'REVIEW', label: 'Review' },
  { key: 'DONE', label: 'Done' },
];

type Task = {
  id: string; title: string; description?: string | null;
  status: string; priority: string; dueAt?: string | null;
  assignees: { user: { id: string; name: string; avatarUrl?: string | null; isClient: boolean; role: string } }[];
};

export default function TasksPage() {
  const qc = useQueryClient();
  const [creating, setCreating] = useState(false);
  const [title, setTitle] = useState('');

  const { data, isLoading } = useQuery<{ view: 'kanban'; columns: Record<string, Task[]> }>({
    queryKey: ['tasks.kanban'],
    queryFn: async () => (await api.get('/tasks', { params: { view: 'kanban' } })).data,
  });

  const createMut = useMutation({
    mutationFn: async (t: { title: string; status: string }) =>
      (await api.post('/tasks', { title: t.title, status: t.status })).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks.kanban'] }),
  });

  const moveMut = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) =>
      (await api.post(`/tasks/${id}/move`, { status })).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['tasks.kanban'] }),
  });

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
          <p className="tk__sub">Realtime kanban — drag cards to update status.</p>
        </div>
        <Button onClick={() => setCreating((v) => !v)}><Plus size={16}/> New task</Button>
      </header>

      {creating && (
        <div className="tk__quick">
          <input
            autoFocus
            placeholder="What needs to happen?"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && title.trim()) {
                createMut.mutate({ title: title.trim(), status: 'TODO' });
                setTitle('');
                setCreating(false);
              }
            }}
          />
        </div>
      )}

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
              {(data?.columns?.[col.key] || []).map((t) => (
                <article
                  key={t.id}
                  draggable
                  onDragStart={(e) => onDragStart(e, t.id)}
                  className={`tk__card tk__card--${t.priority.toLowerCase()}`}
                >
                  <div className="tk__card-head">
                    <GripVertical size={14} className="tk__drag" />
                    <span className="tk__card-title">{t.title}</span>
                  </div>
                  <div className="tk__card-foot">
                    <div className="tk__avatars">
                      {t.assignees.slice(0, 3).map((a) => (
                        <Avatar key={a.user.id} name={a.user.name} src={a.user.avatarUrl} isClient={a.user.isClient} size={22} />
                      ))}
                    </div>
                    {t.dueAt && (
                      <span className="tk__due"><Calendar size={12} /> {dayjs(t.dueAt).format('MMM D')}</span>
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
              ))}
              {!isLoading && (data?.columns?.[col.key]?.length ?? 0) === 0 && (
                <div className="tk__col-empty">Drop here</div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
