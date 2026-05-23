import { ChangeEvent, DragEvent, FormEvent, KeyboardEvent, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Send, Hash, Pin, Paperclip, X } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { getSocket } from '@/services/socket';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { toast } from '@/components/Toast';
import './chat.css';

type ChannelMember = {
  userId: string;
  user?: {
    id: string;
    userId: string;
    name: string;
    avatarUrl?: string | null;
    isClient: boolean;
    role: string;
    customTitle?: string | null;
  };
};

type Channel = {
  id: string;
  name: string | null;
  kind: string;
  isClientChannel: boolean;
  pinned: boolean;
  members: ChannelMember[];
};

type Message = {
  id: string;
  body: string | null;
  authorId: string;
  author: { id: string; name: string; avatarUrl?: string | null; isClient: boolean; role: string };
  createdAt: string;
  pinned: boolean;
  attachments?: Array<{ id: string; url: string; mimeType: string; originalName?: string | null }>;
};

type MentionPick = {
  id: string;
  userId: string;
  name: string;
  role: string;
  customTitle?: string | null;
  avatarUrl?: string | null;
  isClient: boolean;
};

export default function ChatPage() {
  const { channelId } = useParams();
  const navigate = useNavigate();
  const me = useAuthStore((s) => s.user)!;
  const qc = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [draft, setDraft] = useState('');
  const [uploading, setUploading] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const [pendingAttachments, setPendingAttachments] = useState<Array<{ id: string; url: string; mimeType: string; originalName?: string | null }>>([]);
  const [mentionIndex, setMentionIndex] = useState(0);

  const { data: channelsData } = useQuery<{ items: Channel[] }>({
    queryKey: ['channels.mine'],
    queryFn: async () => (await api.get('/channels')).data,
  });
  const channels = channelsData?.items || [];
  const active = channels.find((c) => c.id === channelId) || channels[0];

  useEffect(() => {
    if (!channelId && active) navigate(`/chat/${active.id}`, { replace: true });
  }, [channelId, active, navigate]);

  const { data: messagesData } = useQuery<{ items: Message[]; nextCursor: string | null }>({
    queryKey: ['chat.messages', active?.id],
    queryFn: async () => (await api.get(`/chat/channels/${active!.id}/messages`)).data,
    enabled: !!active,
  });
  const messages = useMemo(() => messagesData?.items || [], [messagesData]);

  const memberSuggestions = useMemo<MentionPick[]>(() => {
    const members = (active?.members || [])
      .map((member) => member.user)
      .filter((user): user is NonNullable<typeof user> => !!user)
      .filter((user) => user.id !== me.id)
      .map((user) => ({
        id: user.id,
        userId: user.userId,
        name: user.name,
        role: user.role,
        customTitle: user.customTitle,
        avatarUrl: user.avatarUrl,
        isClient: user.isClient,
      }));
    const match = draft.match(/(?:^|\s)@([^\s@]*)$/);
    if (!match) return [];
    const query = match[1].toLowerCase();
    return members
      .filter((user) => {
        if (!query) return true;
        return user.name.toLowerCase().includes(query) || user.userId.toLowerCase().includes(query);
      })
      .slice(0, 6);
  }, [active?.members, draft, me.id]);

  useEffect(() => {
    setMentionIndex(0);
  }, [draft, active?.id]);

  useEffect(() => {
    if (!active) return;
    const s = getSocket();
    if (!s) return;
    s.emit('channel.join', active.id);
    const onNew = (m: Message) => {
      if (m.author?.id) {
        qc.setQueryData<{ items: Message[]; nextCursor: string | null }>(['chat.messages', active.id], (prev) =>
          prev ? { ...prev, items: [...prev.items, m] } : { items: [m], nextCursor: null }
        );
      }
    };
    s.on('chat.message.created', onNew);
    return () => {
      s.off('chat.message.created', onNew);
    };
  }, [active, qc]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages.length, pendingAttachments.length]);

  async function uploadSelectedFiles(files: File[]) {
    if (!files.length) return;
    setUploading(true);
    try {
      const uploaded: Array<{ id: string; url: string; mimeType: string; originalName?: string | null }> = [];
      for (const file of files) {
        const formData = new FormData();
        formData.append('file', file);
        const { data } = await api.post('/files/upload', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        });
        uploaded.push(data);
      }
      setPendingAttachments((prev) => [...prev, ...uploaded]);
      toast.success(`${uploaded.length} file${uploaded.length === 1 ? '' : 's'} attached`);
    } catch (err: any) {
      toast.error(err?.response?.data?.error?.message || 'Could not upload file');
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  }

  async function uploadFiles(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files || []);
    await uploadSelectedFiles(files);
  }

  function onDragOver(e: DragEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!active) return;
    if (!dragActive) setDragActive(true);
  }

  function onDragLeave(e: DragEvent<HTMLFormElement>) {
    e.preventDefault();
    const nextTarget = e.relatedTarget as Node | null;
    if (nextTarget && e.currentTarget.contains(nextTarget)) return;
    setDragActive(false);
  }

  async function onDropFiles(e: DragEvent<HTMLFormElement>) {
    e.preventDefault();
    setDragActive(false);
    const files = Array.from(e.dataTransfer.files || []);
    await uploadSelectedFiles(files);
  }

  function applyMention(person: MentionPick) {
    setDraft((prev) => prev.replace(/(^|\s)@([^\s@]*)$/, `$1@${person.userId} `));
  }

  async function send(e: FormEvent) {
    e.preventDefault();
    if (!active || (!draft.trim() && pendingAttachments.length === 0)) return;
    const body = draft.trim();
    const attachmentIds = pendingAttachments.map((file) => file.id);
    setDraft('');
    setPendingAttachments([]);
    await api.post(`/chat/channels/${active.id}/messages`, {
      body: body || null,
      kind: attachmentIds.length && !body ? 'FILE' : 'TEXT',
      attachmentIds,
    });
  }

  function onComposerKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (!memberSuggestions.length) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setMentionIndex((prev) => (prev + 1) % memberSuggestions.length);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setMentionIndex((prev) => (prev - 1 + memberSuggestions.length) % memberSuggestions.length);
    } else if (e.key === 'Enter') {
      const match = draft.match(/(?:^|\s)@([^\s@]*)$/);
      if (match) {
        e.preventDefault();
        applyMention(memberSuggestions[mentionIndex] || memberSuggestions[0]);
      }
    } else if (e.key === 'Escape') {
      setDraft((prev) => prev.replace(/(^|\s)@([^\s@]*)$/, '$1'));
    }
  }

  return (
    <div className="ch">
      <aside className="ch__list">
        <header className="ch__list-head"><Hash size={16} /><span>Channels</span></header>
        <ul>
          {channels.map((c) => (
            <li
              key={c.id}
              className={c.id === active?.id ? 'is-active' : ''}
              onClick={() => navigate(`/chat/${c.id}`)}
            >
              <span className="ch__list-name">
                <Hash size={14} />
                <span className={c.isClientChannel ? 'client-name' : ''}>
                  {c.name || c.members.find((m) => m.userId !== me.id)?.user?.name || 'Direct message'}
                </span>
              </span>
              {c.pinned && <Pin size={12} className="ch__pin" />}
            </li>
          ))}
          {channels.length === 0 && <li className="ch__empty">No channels yet.</li>}
        </ul>
      </aside>

      <section className="ch__panel">
        {active ? (
          <>
            <header className="ch__panel-head">
              <div>
                <div className="ch__title">
                  <Hash size={16} /> <span>{active.name || 'Direct message'}</span>
                  {active.isClientChannel && <span className="client-chip" style={{ marginLeft: 8 }}>CLIENT</span>}
                </div>
                <div className="ch__sub">{active.members.length} members</div>
              </div>
            </header>

            <div className="ch__messages" ref={scrollRef}>
              {messages.map((m) => (
                <div key={m.id} className="ch__msg">
                  <Avatar name={m.author.name} src={m.author.avatarUrl} isClient={m.author.isClient} size={32} />
                  <div className="ch__msg-body">
                    <div className="ch__msg-meta">
                      <UserName name={m.author.name} isClient={m.author.isClient} role={m.author.role} />
                      <span className="ch__msg-time">{dayjs(m.createdAt).format('HH:mm')}</span>
                    </div>
                    {m.body && <div className="ch__msg-text">{m.body}</div>}
                    {!!m.attachments?.length && (
                      <div className="ch__attachments">
                        {m.attachments.map((file) => (
                          <a key={file.id} className="ch__attachment" href={file.url} target="_blank" rel="noreferrer">
                            {file.mimeType?.startsWith('image/') ? (
                              <img src={file.url} alt={file.originalName || 'attachment'} />
                            ) : (
                              <span>{file.originalName || 'Attachment'}</span>
                            )}
                          </a>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              ))}
              {messages.length === 0 && <div className="ch__empty-center">No messages yet — start the conversation.</div>}
            </div>

            <form
              className={`ch__composer ${dragActive ? 'is-dragging' : ''}`}
              onSubmit={send}
              onDragOver={onDragOver}
              onDragLeave={onDragLeave}
              onDrop={onDropFiles}
            >
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={onComposerKeyDown}
                placeholder={`Message ${active.name || ''}…`}
              />
              <input ref={fileInputRef} type="file" multiple hidden onChange={uploadFiles} />
              <button type="button" className="ch__icon-btn" onClick={() => fileInputRef.current?.click()} disabled={uploading}>
                <Paperclip size={16} />
              </button>
              <button type="submit" disabled={!draft.trim() && pendingAttachments.length === 0}><Send size={16} /></button>
              {!!memberSuggestions.length && (
                <div className="ch__mentions">
                  {memberSuggestions.map((person, index) => (
                    <button
                      type="button"
                      key={person.id}
                      className={`ch__mention-item ${index === mentionIndex ? 'is-active' : ''}`}
                      onClick={() => applyMention(person)}
                    >
                      <Avatar name={person.name} src={person.avatarUrl} isClient={person.isClient} size={24} />
                      <div>
                        <strong>{person.name}</strong>
                        <span>@{person.userId} · {person.customTitle || person.role.replace(/_/g, ' ')}</span>
                      </div>
                    </button>
                  ))}
                </div>
              )}
              {dragActive && (
                <div className="ch__dropzone">
                  <strong>Drop files to attach</strong>
                  <span>Images, docs, and other files will be added to this message.</span>
                </div>
              )}
            </form>
            {!!pendingAttachments.length && (
              <div className="ch__pending-files">
                {pendingAttachments.map((file) => (
                  <div key={file.id} className="ch__pending-file">
                    <span>{file.originalName || 'Attachment ready'}</span>
                    <button type="button" onClick={() => setPendingAttachments((prev) => prev.filter((item) => item.id !== file.id))}>
                      <X size={14} />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </>
        ) : (
          <div className="ch__empty-center">Pick a channel to start chatting.</div>
        )}
      </section>
    </div>
  );
}
