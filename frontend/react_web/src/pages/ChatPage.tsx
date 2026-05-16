import { FormEvent, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Send, Hash, Pin } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { getSocket } from '@/services/socket';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import './chat.css';

type Channel = {
  id: string;
  name: string | null;
  kind: string;
  isClientChannel: boolean;
  pinned: boolean;
  members: any[];
};

type Message = {
  id: string;
  body: string | null;
  authorId: string;
  author: { id: string; name: string; avatarUrl?: string | null; isClient: boolean; role: string };
  createdAt: string;
  pinned: boolean;
  attachments?: any[];
};

export default function ChatPage() {
  const { channelId } = useParams();
  const navigate = useNavigate();
  const me = useAuthStore((s) => s.user)!;
  const qc = useQueryClient();
  const [draft, setDraft] = useState('');
  const scrollRef = useRef<HTMLDivElement>(null);

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
  }, [messages.length]);

  async function send(e: FormEvent) {
    e.preventDefault();
    if (!active || !draft.trim()) return;
    const body = draft.trim();
    setDraft('');
    await api.post(`/chat/channels/${active.id}/messages`, { body });
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
                    <div className="ch__msg-text">{m.body}</div>
                  </div>
                </div>
              ))}
              {messages.length === 0 && <div className="ch__empty-center">No messages yet — start the conversation.</div>}
            </div>

            <form className="ch__composer" onSubmit={send}>
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder={`Message ${active.name || ''}…`}
              />
              <button type="submit" disabled={!draft.trim()}><Send size={16} /></button>
            </form>
          </>
        ) : (
          <div className="ch__empty-center">Pick a channel to start chatting.</div>
        )}
      </section>
    </div>
  );
}
