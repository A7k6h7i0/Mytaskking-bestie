import { ChangeEvent, ClipboardEvent, DragEvent, FormEvent, KeyboardEvent, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Send, Hash, Pin, Paperclip, X, ClipboardPaste, RotateCcw, GripVertical, Mic, Square, ChevronLeft, ChevronRight } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { getSocket } from '@/services/socket';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
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
  unreadCount?: number;
  members: ChannelMember[];
};

type Message = {
  id: string;
  channelId: string;
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

type PendingAttachment = {
  tempId: string;
  id?: string;
  url?: string;
  mimeType?: string;
  originalName?: string | null;
  progress: number;
  status: 'uploading' | 'ready' | 'error';
  sourceFile?: File;
};

function makeTempId(file: File) {
  return `${file.name}-${file.size}-${file.lastModified}-${Math.random().toString(36).slice(2, 8)}`;
}

export default function ChatPage() {
  const { channelId } = useParams();
  const navigate = useNavigate();
  const me = useAuthStore((s) => s.user)!;
  const qc = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const panelRef = useRef<HTMLElement | null>(null);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const audioChunksRef = useRef<BlobPart[]>([]);
  const uploadControllersRef = useRef<Record<string, AbortController>>({});
  const [draft, setDraft] = useState('');
  const [uploading, setUploading] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const [dragDepth, setDragDepth] = useState(0);
  const [pendingAttachments, setPendingAttachments] = useState<PendingAttachment[]>([]);
  const [mentionIndex, setMentionIndex] = useState(0);
  const [dragAttachmentId, setDragAttachmentId] = useState<string | null>(null);
  const [lightbox, setLightbox] = useState<{ items: Array<{ url: string; name: string }>; index: number } | null>(null);
  const [recording, setRecording] = useState(false);

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

  const readyAttachments = useMemo(() => pendingAttachments.filter((file) => file.status === 'ready' && file.id), [pendingAttachments]);
  const hasUploading = pendingAttachments.some((file) => file.status === 'uploading');

  useEffect(() => {
    setMentionIndex(0);
  }, [draft, active?.id]);

  useEffect(() => {
    if (!active) return;
    const s = getSocket();
    if (!s) return;
    s.emit('channel.join', active.id);
    const onNew = (m: Message) => {
      if (m.channelId !== active.id) return;
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
    if (!active?.id) return;
    api.post(`/chat/channels/${active.id}/read`)
      .then(() => qc.invalidateQueries({ queryKey: ['channels.mine'] }))
      .catch(() => {});
  }, [active?.id, messages.length, qc]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages.length, pendingAttachments.length]);

  async function uploadSelectedFiles(files: File[]) {
    if (!files.length) return;
    setUploading(true);
    const tempEntries = files.map((file) => ({
      tempId: makeTempId(file),
      originalName: file.name,
      mimeType: file.type,
      progress: 0,
      status: 'uploading' as const,
      sourceFile: file,
    }));
    setPendingAttachments((prev) => [...prev, ...tempEntries]);
    await uploadEntries(tempEntries);
  }

  async function uploadEntries(entries: PendingAttachment[]) {
    if (!entries.length) return;

    const results = await Promise.allSettled(entries.map(async (entry) => {
        const file = entry.sourceFile;
        if (!file) return;
        const tempId = entry.tempId;
        const controller = new AbortController();
        uploadControllersRef.current[tempId] = controller;
        const formData = new FormData();
        formData.append('file', file);
        const { data } = await api.post('/files/upload', formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
          signal: controller.signal,
          onUploadProgress: (event) => {
            const total = event.total || file.size || 1;
            const progress = Math.max(5, Math.min(100, Math.round(((event.loaded || 0) / total) * 100)));
            setPendingAttachments((prev) => prev.map((item) => item.tempId === tempId ? { ...item, progress } : item));
          },
        });
        setPendingAttachments((prev) => prev.map((item) => item.tempId === tempId ? {
          ...item,
          id: data.id,
          url: data.url,
          mimeType: data.mimeType,
          originalName: data.originalName,
          progress: 100,
          status: 'ready',
        } : item));
        delete uploadControllersRef.current[tempId];
      }));

    const failures = results.filter((result) => result.status === 'rejected');
    if (failures.length) {
      const failedIds = new Set(
        entries
          .filter((entry, index) => results[index]?.status === 'rejected')
          .map((entry) => entry.tempId)
      );
      setPendingAttachments((prev) =>
        prev.map((item) => failedIds.has(item.tempId) && item.status === 'uploading' ? { ...item, status: 'error' } : item)
      );
      toast.error(failures.length === entries.length ? 'Could not upload file' : `${failures.length} upload${failures.length === 1 ? '' : 's'} failed`);
    }
    const successCount = results.length - failures.length;
    if (successCount > 0) {
      toast.success(`${successCount} file${successCount === 1 ? '' : 's'} attached`);
    }

    setUploading(Object.keys(uploadControllersRef.current).length > 0);
    if (fileInputRef.current) fileInputRef.current.value = '';
  }

  async function uploadFiles(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files || []);
    await uploadSelectedFiles(files);
  }

  function onDragOver(e: DragEvent<HTMLElement>) {
    e.preventDefault();
    if (!active) return;
    e.dataTransfer.dropEffect = 'copy';
  }

  function onDragEnter(e: DragEvent<HTMLElement>) {
    e.preventDefault();
    if (!active) return;
    setDragDepth((prev) => prev + 1);
    setDragActive(true);
  }

  function onDragLeave(e: DragEvent<HTMLElement>) {
    e.preventDefault();
    if (!active) return;
    const nextDepth = Math.max(0, dragDepth - 1);
    setDragDepth(nextDepth);
    if (nextDepth === 0) setDragActive(false);
  }

  async function onDropFiles(e: DragEvent<HTMLElement>) {
    e.preventDefault();
    setDragActive(false);
    setDragDepth(0);
    const files = Array.from(e.dataTransfer.files || []);
    await uploadSelectedFiles(files);
  }

  async function onPaste(e: ClipboardEvent<HTMLInputElement>) {
    const files = Array.from(e.clipboardData.items || [])
      .filter((item) => item.kind === 'file')
      .map((item) => item.getAsFile())
      .filter((file): file is File => !!file);
    if (!files.length) return;
    e.preventDefault();
    await uploadSelectedFiles(files);
    toast.info('Pasted image attached');
  }

  async function retryAttachment(tempId: string) {
    const entry = pendingAttachments.find((item) => item.tempId === tempId);
    if (!entry?.sourceFile) return;
    setUploading(true);
    setPendingAttachments((prev) => prev.map((item) => item.tempId === tempId ? { ...item, status: 'uploading', progress: 0 } : item));
    await uploadEntries([{ ...entry, status: 'uploading', progress: 0 }]);
  }

  function cancelUpload(tempId: string) {
    uploadControllersRef.current[tempId]?.abort();
    delete uploadControllersRef.current[tempId];
    setPendingAttachments((prev) => prev.filter((item) => item.tempId !== tempId));
    setUploading(Object.keys(uploadControllersRef.current).length > 0);
    toast.info('Upload cancelled');
  }

  function movePendingAttachment(fromId: string, toId: string) {
    if (fromId === toId) return;
    setPendingAttachments((prev) => {
      const next = [...prev];
      const fromIndex = next.findIndex((item) => item.tempId === fromId);
      const toIndex = next.findIndex((item) => item.tempId === toId);
      if (fromIndex === -1 || toIndex === -1) return prev;
      const [picked] = next.splice(fromIndex, 1);
      next.splice(toIndex, 0, picked);
      return next;
    });
  }

  function applyMention(person: MentionPick) {
    setDraft((prev) => prev.replace(/(^|\s)@([^\s@]*)$/, `$1@${person.userId} `));
  }

  async function send(e: FormEvent) {
    e.preventDefault();
    if (!active || (!draft.trim() && readyAttachments.length === 0) || hasUploading) return;
    const body = draft.trim();
    const attachmentIds = readyAttachments.map((file) => file.id!).filter(Boolean);
    const onlyAudio = !body && readyAttachments.length > 0 && readyAttachments.every((file) => file.mimeType?.startsWith('audio/'));
    setDraft('');
    setPendingAttachments([]);
    await api.post(`/chat/channels/${active.id}/messages`, {
      body: body || null,
      kind: onlyAudio ? 'VOICE_NOTE' : attachmentIds.length && !body ? 'FILE' : 'TEXT',
      attachmentIds,
    });
  }

  async function toggleRecording() {
    if (recording) {
      mediaRecorderRef.current?.stop();
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaStreamRef.current = stream;
      const recorder = new MediaRecorder(stream);
      audioChunksRef.current = [];
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) audioChunksRef.current.push(event.data);
      };
      recorder.onstop = async () => {
        setRecording(false);
        const blob = new Blob(audioChunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        if (blob.size > 0) {
          const ext = recorder.mimeType.includes('ogg') ? 'ogg' : recorder.mimeType.includes('mp4') ? 'm4a' : 'webm';
          const file = new File([blob], `voice-note-${Date.now()}.${ext}`, { type: recorder.mimeType || 'audio/webm' });
          await uploadSelectedFiles([file]);
        }
        mediaStreamRef.current?.getTracks().forEach((track) => track.stop());
        mediaStreamRef.current = null;
      };
      mediaRecorderRef.current = recorder;
      recorder.start();
      setRecording(true);
      toast.info('Recording voice note…');
    } catch (err: any) {
      toast.error(err?.message || 'Microphone access was not available');
    }
  }

  useEffect(() => {
    return () => {
      mediaStreamRef.current?.getTracks().forEach((track) => track.stop());
      Object.values(uploadControllersRef.current).forEach((controller) => controller.abort());
    };
  }, []);

  function openImageGallery(attachments: Array<{ id: string; url: string; mimeType: string; originalName?: string | null }>, clickedId: string) {
    const images = attachments
      .filter((attachment) => attachment.mimeType?.startsWith('image/'))
      .map((attachment) => ({ id: attachment.id, url: attachment.url, name: attachment.originalName || 'image' }));
    const index = Math.max(0, images.findIndex((item) => item.id === clickedId));
    setLightbox({ items: images.map(({ url, name }) => ({ url, name })), index });
  }

  function shiftLightbox(direction: -1 | 1) {
    setLightbox((current) => {
      if (!current) return current;
      const nextIndex = (current.index + direction + current.items.length) % current.items.length;
      return { ...current, index: nextIndex };
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
            (() => {
              const unread = c.id === active?.id ? 0 : c.unreadCount || 0;
              return (
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
                  <span className="ch__list-actions">
                    {unread > 0 && <span className="ch__unread">{unread > 99 ? '99+' : unread}</span>}
                    {c.pinned && <Pin size={12} className="ch__pin" />}
                  </span>
                </li>
              );
            })()
          ))}
          {channels.length === 0 && <li className="ch__empty">No channels yet.</li>}
        </ul>
      </aside>

      <section
        ref={panelRef}
        className={`ch__panel ${dragActive ? 'is-dragging' : ''}`}
        onDragEnter={onDragEnter}
        onDragOver={onDragOver}
        onDragLeave={onDragLeave}
        onDrop={onDropFiles}
      >
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
                <div key={m.id} className={`ch__msg ${m.authorId === me.id ? 'ch__msg--mine' : 'ch__msg--other'}`}>
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
                          <a
                            key={file.id}
                            className="ch__attachment"
                            href={file.url}
                            target={file.mimeType?.startsWith('image/') ? undefined : '_blank'}
                            rel="noreferrer"
                            onClick={(e) => {
                              if (file.mimeType?.startsWith('image/')) {
                                e.preventDefault();
                                openImageGallery(m.attachments || [], file.id);
                              }
                            }}
                          >
                            {file.mimeType?.startsWith('image/') ? (
                              <img src={file.url} alt={file.originalName || 'attachment'} />
                            ) : file.mimeType?.startsWith('audio/') ? (
                              <audio controls preload="metadata" className="ch__audio">
                                <source src={file.url} type={file.mimeType} />
                              </audio>
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
              onDragEnter={onDragEnter}
              onDragOver={onDragOver}
              onDragLeave={onDragLeave}
              onDrop={onDropFiles}
            >
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={onComposerKeyDown}
                onPaste={onPaste}
                placeholder={`Message ${active.name || ''}…`}
              />
              <input ref={fileInputRef} type="file" multiple hidden onChange={uploadFiles} />
              <button type="button" className="ch__icon-btn" onClick={() => fileInputRef.current?.click()} disabled={uploading}>
                <Paperclip size={16} />
              </button>
              <button type="button" className={`ch__icon-btn ${recording ? 'is-recording' : ''}`} onClick={toggleRecording} disabled={uploading}>
                {recording ? <Square size={16} /> : <Mic size={16} />}
              </button>
              <button type="submit" disabled={(!draft.trim() && readyAttachments.length === 0) || hasUploading}><Send size={16} /></button>
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
                  <strong>Drop files anywhere in this chat</strong>
                  <span>Images, docs, and other files will be attached to your next message.</span>
                </div>
              )}
            </form>
            {!!pendingAttachments.length && (
              <div className="ch__pending-files">
                {pendingAttachments.map((file) => (
                  <div
                    key={file.tempId}
                    className={`ch__pending-file ch__pending-file--${file.status}`}
                    draggable
                    onDragStart={() => setDragAttachmentId(file.tempId)}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={(e) => {
                      e.preventDefault();
                      if (dragAttachmentId) movePendingAttachment(dragAttachmentId, file.tempId);
                      setDragAttachmentId(null);
                    }}
                    onDragEnd={() => setDragAttachmentId(null)}
                  >
                    <span className="ch__drag-handle" aria-hidden="true"><GripVertical size={14} /></span>
                    <div className="ch__pending-meta">
                      <span>{file.originalName || 'Attachment ready'}</span>
                      {file.status === 'uploading' && <small>{file.progress}%</small>}
                      {file.status === 'error' && <small>Upload failed</small>}
                      {file.status === 'ready' && <small>Ready</small>}
                    </div>
                    <div className="ch__pending-actions">
                      {file.status === 'uploading' && <div className="ch__pending-bar"><i style={{ width: `${file.progress}%` }} /></div>}
                      {file.status === 'uploading' && (
                        <button type="button" className="ch__retry-btn" onClick={() => cancelUpload(file.tempId)} title="Cancel upload">
                          <X size={14} />
                        </button>
                      )}
                      {file.status === 'error' && (
                        <button type="button" className="ch__retry-btn" onClick={() => retryAttachment(file.tempId)} title="Retry upload">
                          <RotateCcw size={14} />
                        </button>
                      )}
                      <button type="button" onClick={() => setPendingAttachments((prev) => prev.filter((item) => item.tempId !== file.tempId))}>
                        <X size={14} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
            <div className="ch__helper-row">
              <span><ClipboardPaste size={14} /> Paste images from your clipboard directly into the composer.</span>
              <span>Drag files anywhere over this chat panel, drag chips to re-order them, or record a voice note.</span>
            </div>
          </>
        ) : (
          <div className="ch__empty-center">Pick a channel to start chatting.</div>
        )}
      </section>
      <Modal
        open={!!lightbox}
        onClose={() => setLightbox(null)}
        title={lightbox ? lightbox.items[lightbox.index]?.name || 'Image preview' : 'Image preview'}
        description="Full-size chat image preview"
        footer={
          lightbox ? (
            <>
              {lightbox.items.length > 1 && <Button variant="ghost" onClick={() => shiftLightbox(-1)}><ChevronLeft size={16} /> Previous</Button>}
              {lightbox.items.length > 1 && <Button variant="ghost" onClick={() => shiftLightbox(1)}>Next <ChevronRight size={16} /></Button>}
              <Button variant="ghost" onClick={() => setLightbox(null)}>Close</Button>
            </>
          ) : undefined
        }
      >
        {lightbox && (
          <div className="ch__lightbox">
            <img src={lightbox.items[lightbox.index]?.url} alt={lightbox.items[lightbox.index]?.name} />
          </div>
        )}
      </Modal>
    </div>
  );
}
