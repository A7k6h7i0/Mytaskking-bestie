import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Hash, User, FileText, KanbanSquare, Headphones, MessageSquare } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import './command-palette.css';

type Hit = { id: string; label: string; sub?: string; isClient?: boolean; goto: string; kind: string };

const ICONS: Record<string, React.ComponentType<{ size?: number }>> = {
  users: User,
  channels: Hash,
  tasks: KanbanSquare,
  messages: MessageSquare,
  files: FileText,
  leads: Headphones,
};

const KIND_LABELS: Record<string, string> = {
  users: 'People',
  channels: 'Channels',
  tasks: 'Tasks',
  messages: 'Messages',
  files: 'Files',
  leads: 'Leads',
};

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [results, setResults] = useState<Record<string, any[]>>({});
  const [loading, setLoading] = useState(false);
  const [active, setActive] = useState(0);
  const navigate = useNavigate();
  const inputRef = useRef<HTMLInputElement>(null);

  // Cmd+K / Ctrl+K toggles the palette globally.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault();
        setOpen((v) => !v);
      } else if (e.key === 'Escape') {
        setOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 30);
    else { setQ(''); setResults({}); setActive(0); }
  }, [open]);

  useEffect(() => {
    if (!q.trim()) { setResults({}); return; }
    const ctrl = new AbortController();
    const t = setTimeout(async () => {
      try {
        setLoading(true);
        const { data } = await api.get('/search', { params: { q, perEntity: 5 }, signal: ctrl.signal });
        setResults(data.results || {});
        setActive(0);
      } catch (_) { /* user typing or cancelled */ }
      finally { setLoading(false); }
    }, 140);
    return () => { ctrl.abort(); clearTimeout(t); };
  }, [q]);

  const flat: Hit[] = [];
  for (const kind of ['channels', 'tasks', 'messages', 'users', 'leads', 'files']) {
    for (const item of results[kind] || []) {
      flat.push(buildHit(kind, item));
    }
  }

  function buildHit(kind: string, item: any): Hit {
    switch (kind) {
      case 'channels':
        return { id: item.id, kind, label: item.name || 'Direct message', sub: item.kind,
                 goto: `/chat/${item.id}`, isClient: item.isClientChannel };
      case 'tasks':
        return { id: item.id, kind, label: item.title, sub: item.status, goto: `/tasks` };
      case 'messages':
        return { id: item.id, kind, label: (item.body || '').slice(0, 120),
                 sub: `#${item.channel?.name || ''} · ${item.author?.name || ''}`,
                 goto: `/chat/${item.channelId}`, isClient: item.channel?.isClientChannel };
      case 'users':
        return { id: item.id, kind, label: item.name, sub: item.role,
                 goto: item.isClient ? '/clients' : '/employees', isClient: item.isClient };
      case 'leads':
        return { id: item.id, kind, label: item.name, sub: `${item.company || ''} · ${item.phone}`, goto: '/telecaller' };
      case 'files':
        return { id: item.id, kind, label: item.originalName || 'file',
                 sub: item.mimeType, goto: item.url };
    }
    return { id: item.id, kind, label: item.id, goto: '/' };
  }

  function go(hit: Hit) {
    setOpen(false);
    if (hit.goto.startsWith('http')) window.open(hit.goto, '_blank');
    else navigate(hit.goto);
  }

  function onKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive((a) => Math.min(a + 1, Math.max(flat.length - 1, 0))); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((a) => Math.max(a - 1, 0)); }
    else if (e.key === 'Enter' && flat[active]) { e.preventDefault(); go(flat[active]); }
  }

  if (!open) return null;

  return (
    <div className="cmdk" onMouseDown={(e) => { if (e.target === e.currentTarget) setOpen(false); }}>
      <div className="cmdk__panel fade-in" role="dialog">
        <div className="cmdk__bar">
          <Search size={18} className="cmdk__search-icon" />
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onKey}
            placeholder="Search people, channels, messages, tasks, files…"
          />
          <kbd>esc</kbd>
        </div>

        <div className="cmdk__body">
          {!q.trim() && (
            <div className="cmdk__hint">
              <p>Jump to anything. Try <span>@priya</span>, <span>onboarding</span>, or <span>#design</span>.</p>
              <div className="cmdk__shortcuts">
                <div><kbd>↑</kbd><kbd>↓</kbd><span>navigate</span></div>
                <div><kbd>↵</kbd><span>open</span></div>
                <div><kbd>esc</kbd><span>close</span></div>
              </div>
            </div>
          )}

          {q.trim() && loading && flat.length === 0 && <div className="cmdk__empty">Searching…</div>}
          {q.trim() && !loading && flat.length === 0 && <div className="cmdk__empty">No matches.</div>}

          {flat.length > 0 && (
            <>
              {['channels', 'tasks', 'messages', 'users', 'leads', 'files'].map((kind) => {
                const hits = flat.filter((h) => h.kind === kind);
                if (hits.length === 0) return null;
                const Icon = ICONS[kind];
                return (
                  <div key={kind} className="cmdk__group">
                    <header>{KIND_LABELS[kind]}</header>
                    {hits.map((hit) => {
                      const idx = flat.indexOf(hit);
                      return (
                        <button
                          key={`${kind}:${hit.id}`}
                          className={clsx('cmdk__hit', idx === active && 'is-active')}
                          onMouseEnter={() => setActive(idx)}
                          onClick={() => go(hit)}
                        >
                          <Icon size={16} />
                          <span className={clsx('cmdk__hit-label', hit.isClient && 'client-name')}>{hit.label}</span>
                          {hit.sub && <span className="cmdk__hit-sub">{hit.sub}</span>}
                        </button>
                      );
                    })}
                  </div>
                );
              })}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
