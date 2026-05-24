import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Hash, Users, Pin, Plus, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/auth';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Modal } from '@/components/ui/Modal';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import './channels.css';

export default function ChannelsPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const user = useAuthStore((s) => s.user)!;
  const [open, setOpen] = useState(false);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [query, setQuery] = useState('');
  const [picked, setPicked] = useState<any[]>([]);
  const canCreateClientChannel = user.role === 'SUPER_ADMIN' || user.role === 'ADMIN';
  const { data, isLoading } = useQuery<{ items: any[] }>({
    queryKey: ['channels.mine'],
    queryFn: async () => (await api.get('/channels')).data,
  });
  const directory = useQuery<{ items: any[] }>({
    queryKey: ['channels.directory', query],
    queryFn: async () => (await api.get('/channels/directory', { params: { q: query || undefined } })).data,
    enabled: open && canCreateClientChannel,
  });
  const createMut = useMutation({
    mutationFn: async () =>
      (await api.post('/channels', {
        name: name.trim(),
        description: description.trim() || null,
        kind: 'CLIENT',
        visibility: 'PRIVATE',
        memberIds: picked.map((person) => person.id),
      })).data,
    onSuccess: (channel) => {
      qc.invalidateQueries({ queryKey: ['channels.mine'] });
      setOpen(false);
      setName('');
      setDescription('');
      setQuery('');
      setPicked([]);
      navigate(`/chat/${channel.id}`);
    },
  });

  const visibleChannels = useMemo(() => {
    return (data?.items || []).filter((channel) => channel.kind !== 'DM');
  }, [data?.items]);

  const candidates = useMemo(() => {
    const pickedIds = new Set(picked.map((person) => person.id));
    return (directory.data?.items || []).filter((person) => person.isClient && !pickedIds.has(person.id));
  }, [directory.data?.items, picked]);

  const pickedClients = useMemo(() => picked.filter((person) => person.isClient), [picked]);

  if (isLoading) return <div className="cn__loading">Loading channels…</div>;

  return (
    <div className="cn">
      <header className="cn__head">
        <div>
          <h1 className="cn__title">Channels</h1>
          <p className="cn__sub">Pinned conversations, team channels, projects, and client workspaces.</p>
        </div>
        {canCreateClientChannel && (
          <Button onClick={() => setOpen(true)}>
            <Plus size={16} /> New channel
          </Button>
        )}
      </header>

      <div className="cn__grid">
        {visibleChannels.map((c) => (
          <article key={c.id} className="cn__card" onClick={() => navigate(`/chat/${c.id}`)}>
            <header className="cn__card-head">
              <div className="cn__card-name">
                <Hash size={16} />
                <span className={c.isClientChannel ? 'client-name' : ''}>{c.name || 'Direct message'}</span>
                {c.pinned && <Pin size={12} className="cn__pin" />}
              </div>
              <span className={`cn__kind cn__kind--${c.kind.toLowerCase()}`}>{c.kind}</span>
            </header>
            <p className="cn__desc">{c.description || 'No description'}</p>
            <footer className="cn__card-foot">
              <span><Users size={12} /> {c.members?.length || 0}</span>
              <span>{c._count?.messages || 0} messages</span>
            </footer>
          </article>
        ))}
        {visibleChannels.length === 0 && <div className="cn__empty">No channels yet. Ask an admin to add you.</div>}
      </div>

      <Modal
        open={open && canCreateClientChannel}
        onClose={() => setOpen(false)}
        title="Create client channel"
        description="Create a client workspace. Active internal users are added automatically."
        footer={
          <>
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={() => createMut.mutate()} loading={createMut.isPending} disabled={!name.trim() || pickedClients.length === 0}>
              Create channel
            </Button>
          </>
        }
      >
        <div className="cn__modal">
          <Input label="Channel name" placeholder="Campaign feedback" value={name} onChange={(e) => setName(e.target.value)} />
          <Input label="Description" placeholder="What this channel is for" value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="cn__picker">
            <span className="cn__picker-label">Add clients</span>
            {picked.length > 0 && (
              <div className="cn__chips">
                {picked.map((person) => (
                  <button type="button" key={person.id} className="cn__chip" onClick={() => setPicked((prev) => prev.filter((item) => item.id !== person.id))}>
                    <Avatar name={person.name} src={person.avatarUrl} isClient={person.isClient} size={18} />
                    <UserName name={person.name} isClient={person.isClient} role={person.role} />
                    <X size={12} />
                  </button>
                ))}
              </div>
            )}
            <Input placeholder="Search clients" value={query} onChange={(e) => setQuery(e.target.value)} />
            <div className="cn__directory">
              {candidates.slice(0, 8).map((person) => (
                <button type="button" key={person.id} className="cn__person" onClick={() => { setPicked((prev) => [...prev, person]); setQuery(''); }}>
                  <Avatar name={person.name} src={person.avatarUrl} isClient={person.isClient} size={24} />
                  <div>
                    <UserName name={person.name} isClient={person.isClient} role={person.role} />
                    <span>{person.customTitle || person.role.replace(/_/g, ' ')} · @{person.userId}</span>
                  </div>
                </button>
              ))}
              {!candidates.length && <div className="cn__directory-empty">No more people to add right now.</div>}
            </div>
          </div>
        </div>
      </Modal>
    </div>
  );
}
