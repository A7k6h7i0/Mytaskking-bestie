import { useEffect, useState } from 'react';
import { Megaphone, X } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import './announcement-banner.css';

type Announcement = {
  id: string;
  title: string;
  body: string;
  priority: 'INFO' | 'IMPORTANT' | 'URGENT';
  acknowledgedBy: string[];
  publishAt: string;
};

export function AnnouncementBanner() {
  const me = useAuthStore((s) => s.user);
  const [items, setItems] = useState<Announcement[]>([]);

  useEffect(() => {
    if (!me) return;
    api.get('/announcements')
      .then(({ data }) => {
        setItems((data.items || []).filter((a: Announcement) => !a.acknowledgedBy?.includes(me.id)));
      })
      .catch(() => {});
  }, [me]);

  if (!me || items.length === 0) return null;
  const top = items[0];

  async function dismiss() {
    await api.post(`/announcements/${top.id}/ack`).catch(() => {});
    setItems((prev) => prev.filter((a) => a.id !== top.id));
  }

  return (
    <div className={clsx('ab', `ab--${top.priority.toLowerCase()}`)}>
      <Megaphone size={16} className="ab__icon" />
      <div className="ab__body">
        <strong>{top.title}</strong>
        <span>{top.body}</span>
      </div>
      <button className="ab__close" onClick={dismiss} title="Dismiss">
        <X size={14} />
      </button>
    </div>
  );
}
