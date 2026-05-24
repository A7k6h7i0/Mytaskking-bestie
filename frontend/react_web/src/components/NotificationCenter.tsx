import { useEffect, useRef, useState } from 'react';
import { Bell, CheckCheck, Settings, MessageSquare, Phone, KanbanSquare, Headphones, Megaphone, type LucideIcon } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import clsx from 'clsx';
import { api } from '@/services/api';
import { getSocket } from '@/services/socket';
import { Skeleton } from '@/components/ui/Skeleton';
import './notification-center.css';

dayjs.extend(relativeTime);

type Notification = {
  id: string;
  kind: 'CHAT' | 'MENTION' | 'TASK' | 'CALL' | 'LEAD_FOLLOWUP' | 'SYSTEM';
  title: string;
  body: string;
  data?: Record<string, unknown> | null;
  readAt: string | null;
  createdAt: string;
};

const CATEGORY_LABEL: Record<string, string> = {
  chat: 'Messages', task: 'Tasks', call: 'Calls', lead: 'Telecaller', system: 'System',
};
const CATEGORY_ICON: Record<string, LucideIcon> = {
  chat: MessageSquare, task: KanbanSquare, call: Phone, lead: Headphones, system: Megaphone,
};

export function NotificationCenter() {
  const [open, setOpen] = useState(false);
  const panelRef = useRef<HTMLDivElement>(null);
  const qc = useQueryClient();

  const { data, isLoading } = useQuery<{ unread: number; groups: Record<string, Notification[]> }>({
    queryKey: ['notifications.grouped'],
    queryFn: async () => (await api.get('/notifications/grouped')).data,
    refetchInterval: open ? 8_000 : 30_000,
  });

  useEffect(() => {
    const s = getSocket();
    if (!s) return;
    const onActivity = () => qc.invalidateQueries({ queryKey: ['notifications.grouped'] });
    s.on('activity.recorded', onActivity);
    s.on('announcement.published', onActivity);
    s.on('notification.created', onActivity);
    return () => {
      s.off('activity.recorded', onActivity);
      s.off('announcement.published', onActivity);
      s.off('notification.created', onActivity);
    };
  }, [qc]);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (!panelRef.current?.contains(e.target as Node)) setOpen(false);
    }
    if (open) document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, [open]);

  async function markAll() {
    await api.post('/notifications/read-all').catch(() => {});
    qc.invalidateQueries({ queryKey: ['notifications.grouped'] });
  }

  return (
    <div className="nc" ref={panelRef}>
      <button
        className={clsx('nc__trigger', open && 'is-open')}
        onClick={() => setOpen((v) => !v)}
        title="Notifications"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label={data && data.unread > 0 ? `Notifications, ${data.unread} unread` : 'Notifications'}
      >
        <Bell size={18} />
        {data && data.unread > 0 && (
          <span className="nc__badge" aria-hidden="true">{data.unread > 99 ? '99+' : data.unread}</span>
        )}
      </button>

      {open && (
        <div className="nc__panel" role="dialog" aria-label="Notifications" aria-live="polite">
          <header className="nc__panel-head">
            <h3>Notifications</h3>
            <div className="nc__actions">
              <button onClick={markAll} title="Mark all read"><CheckCheck size={16} /></button>
              <button title="Preferences"><Settings size={16} /></button>
            </div>
          </header>

          <div className="nc__panel-body">
            {isLoading && (
              <div className="nc__loading">
                <Skeleton height={20} /><Skeleton height={20} /><Skeleton height={20} />
              </div>
            )}
            {!isLoading && Object.keys(data?.groups || {}).length === 0 && (
              <div className="nc__empty">You're all caught up.</div>
            )}
            {!isLoading && Object.entries(data?.groups || {}).map(([cat, items]) => {
              const Icon = CATEGORY_ICON[cat] || Bell;
              return (
                <section key={cat} className="nc__group">
                  <header><Icon size={13} /> {CATEGORY_LABEL[cat] || cat}</header>
                  {items.map((n) => (
                    <div key={n.id} className={clsx('nc__item', !n.readAt && 'is-unread')}>
                      <div className="nc__item-title">{n.title}</div>
                      <div className="nc__item-body">{n.body}</div>
                      <div className="nc__item-time">{dayjs(n.createdAt).fromNow()}</div>
                    </div>
                  ))}
                </section>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
