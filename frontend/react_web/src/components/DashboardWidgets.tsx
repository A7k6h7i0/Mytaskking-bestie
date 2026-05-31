import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { GripVertical, Plus, Trash2, EyeOff, Eye } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { toast } from '@/components/Toast';
import './dashboard-widgets.css';

type Widget = {
  id?: string;
  kind: 'stat.tasks_open' | 'stat.unread' | 'list.recent_tasks' | 'list.recent_messages' | 'activity.feed' | 'calendar.today';
  config?: Record<string, unknown>;
  position: number;
  visible: boolean;
};

const TEMPLATES: Array<{ kind: Widget['kind']; label: string; description: string }> = [
  { kind: 'stat.tasks_open', label: 'Tasks open', description: 'Live count of your open tasks' },
  { kind: 'stat.unread', label: 'Unread alerts', description: 'Unread notifications across all categories' },
  { kind: 'list.recent_tasks', label: 'Recent tasks', description: 'Last 5 tasks you touched' },
  { kind: 'list.recent_messages', label: 'Recent messages', description: 'Latest chat snippets' },
  { kind: 'activity.feed', label: 'Activity feed', description: 'Realtime workspace events (admins only)' },
  { kind: 'calendar.today', label: 'Today\'s events', description: 'Meetings and deadlines for today' },
];

const LABELS: Record<Widget['kind'], string> =
  Object.fromEntries(TEMPLATES.map((t) => [t.kind, t.label])) as Record<Widget['kind'], string>;

/**
 * Configurable dashboard widgets. Loads the user's set, lets them add/remove,
 * reorder via drag handle, and toggle visibility. Persisted via the
 * `/workspace/widgets` API (replace-the-set semantics).
 */
export function DashboardWidgets() {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<Widget[]>([]);

  const { data, isLoading } = useQuery<{ items: Widget[] }>({
    queryKey: ['dashboard.widgets'],
    queryFn: async () => (await api.get('/workspace/widgets')).data,
  });

  useEffect(() => { if (data?.items) setDraft(data.items); }, [data]);

  const save = useMutation({
    mutationFn: async (widgets: Widget[]) =>
      (await api.put('/workspace/widgets', { widgets: widgets.map((w, i) => ({ ...w, position: i })) })).data,
    onSuccess: () => {
      toast.success('Dashboard saved');
      qc.invalidateQueries({ queryKey: ['dashboard.widgets'] });
      setEditing(false);
    },
    onError: () => toast.error('Could not save dashboard'),
  });

  const widgets = useMemo(() => (editing ? draft : (data?.items || [])), [data?.items, draft, editing]);

  function move(from: number, to: number) {
    setDraft((prev) => {
      const next = prev.slice();
      const [it] = next.splice(from, 1);
      next.splice(to, 0, it);
      return next;
    });
  }

  function add(kind: Widget['kind']) {
    setDraft((prev) => [...prev, { kind, position: prev.length, visible: true }]);
  }

  function remove(i: number) {
    setDraft((prev) => prev.filter((_, idx) => idx !== i));
  }

  function toggle(i: number) {
    setDraft((prev) => prev.map((w, idx) => (idx === i ? { ...w, visible: !w.visible } : w)));
  }

  const visible = useMemo(() => widgets.filter((w) => w.visible !== false), [widgets]);

  return (
    <section className="dw">
      <header className="dw__head">
        <h3>Your widgets</h3>
        {!editing ? (
          <Button size="sm" variant="ghost" onClick={() => setEditing(true)}>Customize</Button>
        ) : (
          <div className="dw__head-actions">
            <Button size="sm" variant="ghost" onClick={() => { setEditing(false); setDraft(data?.items || []); }}>Cancel</Button>
            <Button size="sm" onClick={() => save.mutate(draft)} loading={save.isPending}>Save</Button>
          </div>
        )}
      </header>

      {!editing && (
        <div className="dw__grid">
          {isLoading && <div className="dw__hint">Loading widgets…</div>}
          {!isLoading && visible.length === 0 && (
            <div className="dw__empty">No widgets yet — click <em>Customize</em> to pick some.</div>
          )}
          {visible.map((w, i) => (
            <div key={w.id || `${w.kind}:${i}`} className={`dw__widget dw__widget--${w.kind.replace('.', '-')}`}>
              <header>{LABELS[w.kind] || w.kind}</header>
              <div className="dw__widget-body">
                <WidgetBody kind={w.kind} />
              </div>
            </div>
          ))}
        </div>
      )}

      {editing && (
        <div className="dw__edit">
          <div className="dw__edit-list">
            {draft.length === 0 && <div className="dw__hint">Drag widgets from the library to add them.</div>}
            {draft.map((w, i) => (
              <article
                key={`${w.kind}:${i}`}
                className="dw__edit-row"
                draggable
                onDragStart={(e) => e.dataTransfer.setData('text/plain', String(i))}
                onDragOver={(e) => e.preventDefault()}
                onDrop={(e) => { e.preventDefault(); const from = parseInt(e.dataTransfer.getData('text/plain'), 10); if (!Number.isNaN(from) && from !== i) move(from, i); }}
              >
                <GripVertical size={14} className="dw__grip" />
                <span className="dw__edit-label">{LABELS[w.kind] || w.kind}</span>
                <button onClick={() => toggle(i)} title={w.visible ? 'Hide' : 'Show'}>
                  {w.visible ? <Eye size={14}/> : <EyeOff size={14}/>}
                </button>
                <button onClick={() => remove(i)} title="Remove"><Trash2 size={14} /></button>
              </article>
            ))}
          </div>

          <div className="dw__library">
            <header>Widget library</header>
            {TEMPLATES.map((t) => {
              const used = draft.some((w) => w.kind === t.kind);
              return (
                <button
                  key={t.kind}
                  className={clsx('dw__lib-row', used && 'is-used')}
                  onClick={() => !used && add(t.kind)}
                  disabled={used}
                >
                  <Plus size={14} />
                  <span>
                    <strong>{t.label}</strong>
                    <em>{t.description}</em>
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </section>
  );
}

function WidgetBody({ kind }: { kind: Widget['kind'] }) {
  // Widget contents are placeholders — each kind would render its own data
  // hook against the backend. Keeping them visual-only here so the editor
  // story is testable end-to-end before the full per-widget data layer lands.
  switch (kind) {
    case 'stat.tasks_open':       return <div className="dw__placeholder">Open tasks count</div>;
    case 'stat.unread':           return <div className="dw__placeholder">Unread notifications</div>;
    case 'list.recent_tasks':     return <div className="dw__placeholder">Recent tasks list</div>;
    case 'list.recent_messages':  return <div className="dw__placeholder">Recent messages list</div>;
    case 'activity.feed':         return <div className="dw__placeholder">Realtime activity feed</div>;
    case 'calendar.today':        return <div className="dw__placeholder">Today's events</div>;
    default:                      return <div className="dw__placeholder">{kind}</div>;
  }
}
