import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Search, Hash, FileText, KanbanSquare, Headphones, MessageSquare,
  Image as ImageIcon, FileVideo, FileAudio, FileSpreadsheet, FileType, FileArchive,
  Paperclip, AtSign, Filter, Clock, X, ArrowRight,
  type LucideIcon,
} from 'lucide-react';
import clsx from 'clsx';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import './command-palette.css';

dayjs.extend(relativeTime);

type Hit = {
  id: string;
  kind: 'users' | 'channels' | 'tasks' | 'messages' | 'files' | 'leads';
  label: string;
  sub?: string;
  meta?: string;
  isClient?: boolean;
  goto: string;
  external?: boolean;
  raw?: any;
};

const KIND_ICON: Record<string, LucideIcon> = {
  users: AtSign,
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

type Filter = 'all' | 'users' | 'messages' | 'files' | 'channels' | 'tasks';

const FILTERS: { value: Filter; label: string; icon: LucideIcon }[] = [
  { value: 'all',      label: 'All',       icon: Search },
  { value: 'users',    label: 'People',    icon: AtSign },
  { value: 'messages', label: 'Messages',  icon: MessageSquare },
  { value: 'files',    label: 'Files',     icon: FileText },
  { value: 'channels', label: 'Channels',  icon: Hash },
  { value: 'tasks',    label: 'Tasks',     icon: KanbanSquare },
];

const RECENT_KEY = 'cmdk.recents';
const RECENT_MAX = 6;

function readRecents(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed)
      ? parsed.filter((s) => typeof s === 'string').slice(0, RECENT_MAX)
      : [];
  } catch { return []; }
}

function pushRecent(query: string) {
  if (!query.trim()) return;
  const prev = readRecents().filter((q) => q !== query);
  const next = [query, ...prev].slice(0, RECENT_MAX);
  try { localStorage.setItem(RECENT_KEY, JSON.stringify(next)); } catch { /* ignore quota */ }
}

function clearRecents() {
  try { localStorage.removeItem(RECENT_KEY); } catch { /* ignore */ }
}

function formatBytes(n?: number) {
  if (!n) return '';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

function fileIcon(mime?: string): LucideIcon {
  if (!mime) return FileText;
  if (mime.startsWith('image/'))                                              return ImageIcon;
  if (mime.startsWith('video/'))                                              return FileVideo;
  if (mime.startsWith('audio/'))                                              return FileAudio;
  if (mime.includes('pdf'))                                                   return FileType;
  if (mime.includes('sheet') || mime.includes('csv') || mime.includes('excel')) return FileSpreadsheet;
  if (mime.includes('zip')  || mime.includes('rar') || mime.includes('compressed')) return FileArchive;
  return FileText;
}

/** Highlight matched substring inside text — safe (no innerHTML). */
function Highlight({ text, term }: { text: string; term: string }) {
  if (!term || !text) return <>{text}</>;
  const lc = text.toLowerCase();
  const lcTerm = term.toLowerCase();
  const idx = lc.indexOf(lcTerm);
  if (idx === -1) return <>{text}</>;
  return (
    <>
      {text.slice(0, idx)}
      <mark className="cmdk__hl">{text.slice(idx, idx + term.length)}</mark>
      {text.slice(idx + term.length)}
    </>
  );
}

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [results, setResults] = useState<Record<string, any[]>>({});
  const [serverTerm, setServerTerm] = useState('');
  const [loading, setLoading] = useState(false);
  const [active, setActive] = useState(0);
  const [filter, setFilter] = useState<Filter>('all');
  const [recents, setRecents] = useState<string[]>([]);
  const navigate = useNavigate();
  const inputRef = useRef<HTMLInputElement>(null);
  const activeRef = useRef<HTMLButtonElement>(null);

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
    if (open) {
      setTimeout(() => inputRef.current?.focus(), 30);
      setRecents(readRecents());
    } else {
      setQ('');
      setResults({});
      setActive(0);
      setFilter('all');
    }
  }, [open]);

  // Fetch results on query / filter change.
  useEffect(() => {
    if (!q.trim()) { setResults({}); setServerTerm(''); return; }
    const ctrl = new AbortController();
    const t = setTimeout(async () => {
      try {
        setLoading(true);
        const params: Record<string, string | number> = { q, perEntity: 6 };
        if (filter !== 'all') params.kinds = filter;
        const { data } = await api.get('/search', { params, signal: ctrl.signal });
        setResults(data.results || {});
        setServerTerm(data.term ?? q);
        setActive(0);
      } catch (_) { /* aborted */ }
      finally { setLoading(false); }
    }, 160);
    return () => { ctrl.abort(); clearTimeout(t); };
  }, [q, filter]);

  // Flat results — ordered by category for keyboard nav.
  const flat = useMemo<Hit[]>(() => {
    const out: Hit[] = [];
    const order: Hit['kind'][] = ['users', 'messages', 'files', 'channels', 'tasks', 'leads'];
    for (const kind of order) {
      for (const item of results[kind] || []) {
        out.push(buildHit(kind, item));
      }
    }
    return out;
  }, [results]);

  // Auto-scroll active hit into view when navigating.
  useEffect(() => { activeRef.current?.scrollIntoView({ block: 'nearest' }); }, [active]);

  function go(hit: Hit) {
    pushRecent(q);
    setOpen(false);
    if (hit.external) window.open(hit.goto, '_blank', 'noopener,noreferrer');
    else navigate(hit.goto);
  }

  function scopeToPerson(hit: Hit) {
    const handle = hit.raw?.userId || hit.label.split(' ')[0];
    setQ(`from:${handle} `);
    setFilter('messages');
    inputRef.current?.focus();
  }

  function onKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActive((a) => Math.min(a + 1, Math.max(flat.length - 1, 0)));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActive((a) => Math.max(a - 1, 0));
    } else if (e.key === 'Enter' && flat[active]) {
      e.preventDefault();
      go(flat[active]);
    } else if (e.key === 'Tab' && !e.shiftKey) {
      e.preventDefault();
      const i = FILTERS.findIndex((f) => f.value === filter);
      setFilter(FILTERS[(i + 1) % FILTERS.length].value);
    }
  }

  if (!open) return null;

  const showRecents = !q.trim() && recents.length > 0;
  const showHint    = !q.trim();
  const grouped: Record<string, Hit[]> = {};
  for (const h of flat) (grouped[h.kind] ||= []).push(h);

  return (
    <div className="cmdk" onMouseDown={(e) => { if (e.target === e.currentTarget) setOpen(false); }}>
      <div className="cmdk__panel" role="dialog" aria-label="Search workspace">
        <div className="cmdk__bar">
          <Search size={18} className="cmdk__search-icon" />
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onKey}
            placeholder="Search people, messages, files…  try  from:priya  type:pdf"
            aria-label="Search workspace"
            autoComplete="off"
            spellCheck={false}
          />
          {q && (
            <button className="cmdk__clear" onClick={() => { setQ(''); inputRef.current?.focus(); }} aria-label="Clear search">
              <X size={14} />
            </button>
          )}
          <kbd>esc</kbd>
        </div>

        <div className="cmdk__chips" role="tablist" aria-label="Filter results">
          {FILTERS.map(({ value, label, icon: Icon }) => {
            const count = value === 'all'
              ? flat.length
              : (results[value]?.length || 0);
            return (
              <button
                key={value}
                role="tab"
                aria-selected={filter === value}
                className={clsx('cmdk__chip', filter === value && 'is-active')}
                onClick={() => setFilter(value)}
              >
                <Icon size={13} />
                <span>{label}</span>
                {q && count > 0 && <em>{count}</em>}
              </button>
            );
          })}
        </div>

        <div className="cmdk__body">
          {showRecents && (
            <div className="cmdk__group">
              <header>
                <span><Clock size={13} /> Recent</span>
                <button className="cmdk__clear-recents" onClick={() => { clearRecents(); setRecents([]); }}>Clear</button>
              </header>
              {recents.map((r) => (
                <button
                  key={r}
                  className="cmdk__hit cmdk__hit--recent"
                  onClick={() => { setQ(r); inputRef.current?.focus(); }}
                >
                  <Search size={14} />
                  <span className="cmdk__hit-label">{r}</span>
                  <ArrowRight size={14} className="cmdk__hit-arrow" />
                </button>
              ))}
            </div>
          )}

          {showHint && (
            <div className="cmdk__hint">
              <p>Search across everyone, every message, every file.</p>
              <ul className="cmdk__syntax">
                <li><kbd>from:priya</kbd> <span>messages from a person</span></li>
                <li><kbd>in:#design</kbd> <span>messages in a channel</span></li>
                <li><kbd>type:pdf</kbd> <span>files by type</span></li>
              </ul>
              <div className="cmdk__shortcuts">
                <div><kbd>↑</kbd><kbd>↓</kbd><span>navigate</span></div>
                <div><kbd>↵</kbd><span>open</span></div>
                <div><kbd>tab</kbd><span>switch filter</span></div>
                <div><kbd>esc</kbd><span>close</span></div>
              </div>
            </div>
          )}

          {q.trim() && loading && flat.length === 0 && (
            <div className="cmdk__loading">
              <span className="cmdk__loading-dot" />
              <span className="cmdk__loading-dot" />
              <span className="cmdk__loading-dot" />
            </div>
          )}
          {q.trim() && !loading && flat.length === 0 && (
            <div className="cmdk__empty">
              <Filter size={20} />
              <strong>No matches</strong>
              <span>Try a different word, or remove a <kbd>from:</kbd> / <kbd>type:</kbd> filter.</span>
            </div>
          )}

          {flat.length > 0 && (
            <>
              {(['users', 'messages', 'files', 'channels', 'tasks', 'leads'] as const).map((kind) => {
                const hits = grouped[kind];
                if (!hits?.length) return null;
                const Icon = KIND_ICON[kind];
                let runningIdx = 0;
                for (const k of ['users', 'messages', 'files', 'channels', 'tasks', 'leads'] as const) {
                  if (k === kind) break;
                  runningIdx += grouped[k]?.length || 0;
                }
                return (
                  <div key={kind} className={clsx('cmdk__group', `cmdk__group--${kind}`)}>
                    <header><Icon size={13} /> {KIND_LABELS[kind]}</header>
                    {hits.map((hit, i) => {
                      const idx = runningIdx + i;
                      return (
                        <HitRow
                          key={`${kind}:${hit.id}`}
                          hit={hit}
                          term={serverTerm || q}
                          isActive={idx === active}
                          activeRef={idx === active ? activeRef : undefined}
                          onActivate={() => setActive(idx)}
                          onOpen={() => go(hit)}
                          onScopeToPerson={kind === 'users' ? () => scopeToPerson(hit) : undefined}
                        />
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

// ---------- builders ----------

function buildHit(kind: Hit['kind'], item: any): Hit {
  switch (kind) {
    case 'channels':
      return {
        id: item.id,
        kind,
        label: item.name || 'Direct message',
        sub: item.description || item.kind,
        goto: `/chat/${item.id}`,
        isClient: item.isClientChannel,
        raw: item,
      };
    case 'tasks':
      return {
        id: item.id,
        kind,
        label: item.title,
        sub: item.status,
        meta: item.dueAt ? `due ${dayjs(item.dueAt).fromNow()}` : undefined,
        goto: `/tasks`,
        raw: item,
      };
    case 'messages':
      return {
        id: item.id,
        kind,
        label: (item.body || (item.attachments?.length ? '(attachment)' : '')).slice(0, 200),
        sub: `from ${item.author?.name || 'unknown'} · #${item.channel?.name || 'dm'}`,
        meta: dayjs(item.createdAt).fromNow(),
        goto: `/chat/${item.channelId}`,
        isClient: item.channel?.isClientChannel || item.author?.isClient,
        raw: item,
      };
    case 'users':
      return {
        id: item.id,
        kind,
        label: item.name,
        sub: item.customTitle || (item.role || '').replace(/_/g, ' '),
        meta: item.lastSeenAt ? `active ${dayjs(item.lastSeenAt).fromNow()}` : undefined,
        goto: item.isClient ? '/clients' : '/employees',
        isClient: item.isClient,
        raw: item,
      };
    case 'leads':
      return {
        id: item.id,
        kind,
        label: item.name,
        sub: `${item.company || 'No company'} · ${item.phone}`,
        meta: item.status,
        goto: '/telecaller',
        raw: item,
      };
    case 'files': {
      const channel = item.messages?.[0]?.channel;
      const uploader = item.uploadedBy?.name;
      const subParts: string[] = [];
      if (uploader) subParts.push(`shared by ${uploader}`);
      if (channel?.name) subParts.push(`in #${channel.name}`);
      return {
        id: item.id,
        kind,
        label: item.originalName || 'file',
        sub: subParts.join(' · ') || item.mimeType,
        meta: [item.mimeType, formatBytes(item.size)].filter(Boolean).join(' · '),
        goto: channel?.id ? `/chat/${channel.id}` : item.url,
        external: !channel?.id,
        isClient: channel?.isClientChannel || item.uploadedBy?.isClient,
        raw: item,
      };
    }
  }
  return { id: (item as any).id, kind, label: (item as any).id, goto: '/' };
}

// ---------- per-row component ----------

function HitRow({
  hit, term, isActive, activeRef, onActivate, onOpen, onScopeToPerson,
}: {
  hit: Hit;
  term: string;
  isActive: boolean;
  activeRef?: React.RefObject<HTMLButtonElement>;
  onActivate: () => void;
  onOpen: () => void;
  onScopeToPerson?: () => void;
}) {
  if (hit.kind === 'users') {
    return (
      <button
        ref={activeRef}
        className={clsx('cmdk__hit', 'cmdk__hit--person', isActive && 'is-active')}
        onMouseEnter={onActivate}
        onClick={onOpen}
      >
        <Avatar name={hit.label} src={hit.raw?.avatarUrl} isClient={hit.isClient} size={30} />
        <div className="cmdk__hit-main">
          <span className={clsx('cmdk__hit-label', hit.isClient && 'client-name')}>
            <Highlight text={hit.label} term={term} />
          </span>
          {hit.sub && <span className="cmdk__hit-sub">{hit.sub}</span>}
        </div>
        {hit.meta && <span className="cmdk__hit-meta">{hit.meta}</span>}
        {onScopeToPerson && (
          <span
            role="button"
            tabIndex={-1}
            className="cmdk__hit-action"
            onClick={(e) => { e.stopPropagation(); onScopeToPerson(); }}
            title="Search messages from this person"
          >
            <Filter size={12} /> messages
          </span>
        )}
      </button>
    );
  }

  if (hit.kind === 'messages') {
    const r = hit.raw;
    const hasAttachments = (r?.attachments?.length ?? 0) > 0;
    return (
      <button
        ref={activeRef}
        className={clsx('cmdk__hit', 'cmdk__hit--message', isActive && 'is-active')}
        onMouseEnter={onActivate}
        onClick={onOpen}
      >
        <Avatar name={r?.author?.name || '?'} src={r?.author?.avatarUrl} isClient={r?.author?.isClient} size={30} />
        <div className="cmdk__hit-main">
          <div className="cmdk__hit-header">
            <span className={clsx('cmdk__hit-author', r?.author?.isClient && 'client-name')}>
              {r?.author?.name || 'Unknown'}
            </span>
            <span className="cmdk__hit-channel">#{r?.channel?.name || 'dm'}</span>
            {hit.meta && <span className="cmdk__hit-time">{hit.meta}</span>}
          </div>
          <div className="cmdk__hit-snippet">
            <Highlight text={hit.label} term={term} />
            {hasAttachments && (
              <span className="cmdk__hit-attach" title={`${r.attachments.length} attachment(s)`}>
                <Paperclip size={11} /> {r.attachments.length}
              </span>
            )}
          </div>
        </div>
      </button>
    );
  }

  if (hit.kind === 'files') {
    const r = hit.raw;
    const FIcon = fileIcon(r?.mimeType);
    const isImage = (r?.mimeType || '').startsWith('image/');
    const thumb = r?.previewUrl || (isImage ? r?.url : null);
    return (
      <button
        ref={activeRef}
        className={clsx('cmdk__hit', 'cmdk__hit--file', isActive && 'is-active')}
        onMouseEnter={onActivate}
        onClick={onOpen}
      >
        <div className="cmdk__file-thumb">
          {thumb
            ? <img src={thumb} alt="" loading="lazy" />
            : <FIcon size={16} />}
        </div>
        <div className="cmdk__hit-main">
          <span className="cmdk__hit-label">
            <Highlight text={hit.label} term={term} />
          </span>
          {hit.sub && <span className="cmdk__hit-sub">{hit.sub}</span>}
        </div>
        {hit.meta && <span className="cmdk__hit-meta">{hit.meta}</span>}
      </button>
    );
  }

  // channels / tasks / leads — compact row
  const Icon = KIND_ICON[hit.kind];
  return (
    <button
      ref={activeRef}
      className={clsx('cmdk__hit', isActive && 'is-active')}
      onMouseEnter={onActivate}
      onClick={onOpen}
    >
      <Icon size={16} />
      <span className={clsx('cmdk__hit-label', hit.isClient && 'client-name')}>
        <Highlight text={hit.label} term={term} />
      </span>
      {hit.sub && <span className="cmdk__hit-sub">{hit.sub}</span>}
      {hit.meta && <span className="cmdk__hit-meta">{hit.meta}</span>}
    </button>
  );
}
