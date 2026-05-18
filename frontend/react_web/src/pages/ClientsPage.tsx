import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, Search, Trash2, UserX, Calendar } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { UserName } from '@/components/ui/UserName';
import { StatusBadge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { Tooltip } from '@/components/ui/Tooltip';
import { useConfirm } from '@/components/ui/ConfirmDialog';
import { toast } from '@/components/Toast';
import './people.css';

export default function ClientsPage() {
  const qc = useQueryClient();
  const [q, setQ] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [form, setForm] = useState({
    userId: '', password: '', name: '', clientCompany: '', email: '', accessEndsAt: '',
  });
  const { confirm, ConfirmRenderer } = useConfirm();

  const { data, isLoading } = useQuery<{ items: any[] }>({
    queryKey: ['clients', q],
    queryFn: async () => (await api.get('/clients', { params: { q } })).data,
  });

  const createMut = useMutation({
    mutationFn: async () => (await api.post('/clients', form)).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['clients'] });
      setShowNew(false);
      setForm({ userId: '', password: '', name: '', clientCompany: '', email: '', accessEndsAt: '' });
      toast.success('Client added');
    },
    onError: () => toast.error('Could not create client'),
  });

  const extendMut = useMutation({
    mutationFn: async ({ id, accessEndsAt }: { id: string; accessEndsAt: string }) =>
      (await api.post(`/clients/${id}/extend`, { accessEndsAt })).data,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['clients'] }); toast.success('Access extended'); },
  });

  const disableMut = useMutation({
    mutationFn: async (id: string) => (await api.post(`/clients/${id}/disable`)).data,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['clients'] }); toast.success('Client disabled'); },
  });

  const deleteMut = useMutation({
    mutationFn: async (id: string) => (await api.delete(`/clients/${id}`)).data,
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['clients'] }); toast.success('Client deleted'); },
  });

  async function askDisable(u: any) {
    const ok = await confirm({
      title: 'Disable this client?',
      description: 'They will lose access immediately. You can re-enable them later from the same screen.',
      confirmLabel: 'Disable',
      variant: 'warning',
    });
    if (ok) disableMut.mutate(u.id);
  }

  async function askDelete(u: any) {
    const ok = await confirm({
      title: 'Delete client permanently?',
      description: 'This wipes their account, channel memberships, and uploaded files. Cannot be undone.',
      confirmLabel: 'Delete client',
      variant: 'danger',
      confirmText: u.userId,
    });
    if (ok) deleteMut.mutate(u.id);
  }

  return (
    <div className="pp">
      <header className="pp__head">
        <div>
          <h1>Clients</h1>
          <p>Manage external client accounts with time-bound access.</p>
        </div>
        <Button onClick={() => setShowNew((v) => !v)} className="m-press"><Plus size={16}/> New client</Button>
      </header>

      {showNew && (
        <div className="pp__create m-scale-in">
          <Input label="User ID" value={form.userId} onChange={(e) => setForm({ ...form, userId: e.target.value })} />
          <Input label="Password" type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
          <Input label="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <Input label="Client company" value={form.clientCompany} onChange={(e) => setForm({ ...form, clientCompany: e.target.value })} />
          <Input label="Email (optional)" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          <Input label="Access ends at" type="date" value={form.accessEndsAt} onChange={(e) => setForm({ ...form, accessEndsAt: e.target.value })} />
          <div className="pp__create-actions">
            <Button variant="ghost" onClick={() => setShowNew(false)}>Cancel</Button>
            <Button loading={createMut.isPending} onClick={() => createMut.mutate()}>Create</Button>
          </div>
        </div>
      )}

      <div className="pp__filters">
        <Input leading={<Search size={14} />} placeholder="Search clients" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>

      <div className="pp__table">
        <div className="pp__row pp__row--head">
          <span>Client</span><span>Company</span><span>Access until</span><span>Status</span><span></span>
        </div>
        {data?.items.map((u) => (
          <div key={u.id} className="pp__row m-fade-up">
            <span className="pp__name">
              <Avatar name={u.name} src={u.avatarUrl} isClient size={28} />
              <UserName name={u.name} isClient role="CLIENT" />
            </span>
            <span>{u.clientCompany || '—'}</span>
            <span>
              {u.accessEndsAt ? dayjs(u.accessEndsAt).format('MMM D, YYYY') : 'Unlimited'}
              {u.accessEndsAt && (
                <button
                  className="pp__link"
                  onClick={() => {
                    const next = prompt('New access end date (YYYY-MM-DD):', dayjs(u.accessEndsAt).format('YYYY-MM-DD'));
                    if (next) extendMut.mutate({ id: u.id, accessEndsAt: new Date(next).toISOString() });
                  }}
                >Extend</button>
              )}
            </span>
            <span><StatusBadge status={u.status} pulse={u.status === 'ACTIVE'} /></span>
            <span className="pp__actions">
              <Tooltip label="Disable">
                <button className="pp__icon m-press" onClick={() => askDisable(u)} aria-label="Disable client">
                  <UserX size={14} />
                </button>
              </Tooltip>
              <Tooltip label="Delete">
                <button className="pp__icon pp__icon--danger m-press" onClick={() => askDelete(u)} aria-label="Delete client">
                  <Trash2 size={14} />
                </button>
              </Tooltip>
            </span>
          </div>
        ))}
        {!isLoading && !data?.items.length && (
          <EmptyState
            illustration="lock"
            title="No clients yet"
            description="Add your first client and assign them to a channel. Their account expires automatically after the access window you set."
            action={<Button onClick={() => setShowNew(true)}><Plus size={16}/> New client</Button>}
          />
        )}
      </div>

      <ConfirmRenderer />
    </div>
  );
}
