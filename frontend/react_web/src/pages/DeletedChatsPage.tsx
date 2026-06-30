import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Trash2, Building2, MessageSquare, Image, File, Calendar, User } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { SkeletonText } from '@/components/ui/Skeleton';
import './calls.css'; // Reusing calls/recordings-like card layouts for consistency

type DeletedMessage = {
  id: string;
  body: string | null;
  kind: 'TEXT' | 'IMAGE' | 'FILE' | 'VOICE_NOTE' | 'CALL_EVENT';
  deletedAt: string;
  createdAt: string;
  author: {
    id: string;
    userId: string;
    name: string;
    role: string;
    avatarUrl?: string | null;
    isClient?: boolean;
  };
  channel: {
    id: string;
    name: string | null;
    kind: string;
    tenantId: string | null;
  };
  attachments: Array<{
    id: string;
    originalName: string | null;
    mimeType: string | null;
    url: string;
  }>;
};

export default function DeletedChatsPage() {
  const user = useAuthStore((s) => s.user);
  const isPlatformAdmin = user?.role === 'SUPER_ADMIN';
  const [scope, setScope] = useState<'org' | 'platform'>('org');

  const { data, isLoading, isError } = useQuery<{ items: DeletedMessage[]; total: number }>({
    queryKey: ['deleted-chats', scope],
    queryFn: async () => {
      const response = await api.get('/chat/deleted-messages');
      const allItems: DeletedMessage[] = response.data.items || [];

      // Scoping logic on client-side if needed, though backend scopes it automatically.
      // But for Lakshmiraj with 'platform' scope, we want to fetch all.
      // If we are platform admin and scope is 'org', we filter to 'default' or pass tenantSlug.
      // However, `/chat/deleted-messages` handles tenant scoping perfectly on backend.
      // If we want to fetch across all tenants, we let the backend return everything (when tenantId parameter is omitted).
      // If we want to see only our tenant, we can filter or let the backend do it.
      // Let's call the backend with the correct params.
      const params = isPlatformAdmin && scope === 'org' ? { tenantId: user?.tenantId || 'default' } : {};
      return (await api.get('/chat/deleted-messages', { params })).data;
    },
  });

  return (
    <div className="cl">
      <header className="cl__head">
        <div>
          <h1 className="cl__title">Deleted chats</h1>
          <p className="cl__sub">
            {scope === 'platform'
              ? 'All organisations — platform view of deleted chats (super admin only).'
              : 'Deleted employee messages in your organisation.'}
          </p>
        </div>
        {isPlatformAdmin && (
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              type="button"
              className={`cl__person${scope === 'org' ? ' cl__person--active' : ''}`}
              onClick={() => setScope('org')}
            >
              My organisation
            </button>
            <button
              type="button"
              className={`cl__person${scope === 'platform' ? ' cl__person--active' : ''}`}
              onClick={() => setScope('platform')}
            >
              <Building2 size={14} style={{ marginRight: 4, verticalAlign: -2 }} />
              All organisations
            </button>
          </div>
        )}
      </header>

      <div className="cl__list">
        {isLoading && <SkeletonText lines={8} />}

        {isError && (
          <div className="cl__empty">
            <Trash2 size={24} style={{ opacity: 0.5 }} />
            <span>Could not load deleted chats. Please try again.</span>
          </div>
        )}

        {!isLoading && !isError && (data?.items || []).length === 0 && (
          <div className="cl__empty">
            <Trash2 size={24} style={{ opacity: 0.5 }} />
            <span>No deleted messages found. All employee conversations are intact.</span>
          </div>
        )}

        {!isLoading && !isError && (data?.items || []).map((m) => (
          <article key={m.id} className="cl__row" style={{ alignItems: 'flex-start' }}>
            <div className="cl__row-icon" style={{ marginTop: 4 }}>
              <Avatar name={m.author.name} src={m.author.avatarUrl} isClient={m.author.isClient} size={32} />
            </div>
            <div className="cl__row-body" style={{ marginLeft: 12 }}>
              <div className="cl__row-title" style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
                <UserName name={m.author.name} isClient={m.author.isClient} role={m.author.role} />
                <span className="cl__status" style={{ fontSize: 11, padding: '2px 6px' }}>
                  {m.author.userId}
                </span>
                <span className="cl__status" style={{ fontSize: 11, padding: '2px 6px', background: 'var(--c-surface-3)' }}>
                  <MessageSquare size={10} style={{ marginRight: 4, verticalAlign: -1 }} />
                  {m.channel.name || `Channel (${m.channel.kind})`}
                </span>
              </div>

              {/* Message text content */}
              <div style={{ marginTop: 8, fontSize: '14px', color: 'var(--c-text)', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                {m.body ? m.body : <span style={{ fontStyle: 'italic', color: 'var(--c-text-muted)' }}>Empty message body or deleted attachment-only message</span>}
              </div>

              {/* Attachments if any */}
              {m.attachments && m.attachments.length > 0 && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 }}>
                  {m.attachments.map((file) => (
                    <a
                      key={file.id}
                      href={file.url}
                      target="_blank"
                      rel="noreferrer"
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: 6,
                        fontSize: '12px',
                        background: 'var(--c-surface-2)',
                        border: '1px solid var(--c-border)',
                        padding: '4px 8px',
                        borderRadius: 'var(--r-sm)',
                        color: 'var(--c-text-soft)',
                        textDecoration: 'none'
                      }}
                    >
                      {file.mimeType?.startsWith('image/') ? <Image size={12} /> : <File size={12} />}
                      {file.originalName || 'Attachment'}
                    </a>
                  ))}
                </div>
              )}

              {/* Created vs Deleted times */}
              <div style={{ display: 'flex', gap: 16, marginTop: 10, fontSize: '11px', color: 'var(--c-text-muted)' }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  <Calendar size={10} />
                  Sent: {dayjs(m.createdAt).format('YYYY-MM-DD HH:mm:ss')}
                </span>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, color: 'var(--c-danger-strong)' }}>
                  <Trash2 size={10} />
                  Deleted: {dayjs(m.deletedAt).format('YYYY-MM-DD HH:mm:ss')}
                </span>
              </div>
            </div>

            {/* Platform Scope Tenant Label */}
            {isPlatformAdmin && scope === 'platform' && m.channel.tenantId && (
              <div className="cl__row-meta" style={{ flexShrink: 0 }}>
                <span className="cl__status" style={{ background: 'var(--c-brand-soft)', color: 'var(--c-brand-strong)', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  <Building2 size={10} />
                  {m.channel.tenantId === 'default' ? 'MyTaskKing' : m.channel.tenantId}
                </span>
              </div>
            )}
          </article>
        ))}
      </div>
    </div>
  );
}
