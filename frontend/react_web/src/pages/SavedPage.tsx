import { useQuery } from '@tanstack/react-query';
import { Bookmark, MessageSquare, FileText, KanbanSquare, Hash, Headphones } from 'lucide-react';
import { api } from '@/services/api';
import { SkeletonCard } from '@/components/ui/Skeleton';
import './saved.css';

const ICON: Record<string, React.ComponentType<{ size?: number }>> = {
  MESSAGE: MessageSquare,
  FILE: FileText,
  TASK: KanbanSquare,
  CHANNEL: Hash,
  LEAD: Headphones,
};

export default function SavedPage() {
  const { data, isLoading } = useQuery<{ items: any[] }>({
    queryKey: ['saved.mine'],
    queryFn: async () => (await api.get('/saved')).data,
  });

  return (
    <div className="sv">
      <header className="sv__head">
        <div>
          <h1>Saved</h1>
          <p>Bookmarks, starred tasks, pinned channels, and favorite files.</p>
        </div>
      </header>

      <div className="sv__grid">
        {isLoading && <><SkeletonCard /><SkeletonCard /><SkeletonCard /></>}
        {!isLoading && (data?.items || []).map((it) => {
          const Icon = ICON[it.kind] || Bookmark;
          const target = it.target || {};
          return (
            <article key={it.id} className="sv__card">
              <div className="sv__kind"><Icon size={14} /> <span>{it.kind}</span></div>
              <div className="sv__title">{target.title || target.name || target.body?.slice(0, 80) || target.originalName || '—'}</div>
              {it.note && <div className="sv__note">{it.note}</div>}
            </article>
          );
        })}
        {!isLoading && (data?.items.length ?? 0) === 0 && (
          <div className="sv__empty">No saved items. Bookmark a message, star a task, or favorite a file to see it here.</div>
        )}
      </div>
    </div>
  );
}
