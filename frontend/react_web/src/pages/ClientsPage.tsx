import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, Search } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { UserName } from '@/components/ui/UserName';
import './people.css';

export default function ClientsPage() {
  const qc = useQueryClient();
  const [q, setQ] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [form, setForm] = useState({
    userId: '', password: '', name: '', clientCompany: '', email: '', accessEndsAt: '',
  });

  const { data } = useQuery<{ items: any[] }>({
    queryKey: ['clients', q],
    queryFn: async () => (await api.get('/clients', { params: { q } })).data,
  });

  const createMut = useMutation({
    mutationFn: async () => (await api.post('/clients', form)).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['clients'] });
      setShowNew(false);
      setForm({ userId: '', password: '', name: '', clientCompany: '', email: '', accessEndsAt: '' });
    },
  });

  const extendMut = useMutation({
    mutationFn: async ({ id, accessEndsAt }: { id: string; accessEndsAt: string }) =>
      (await api.post(`/clients/${id}/extend`, { accessEndsAt })).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['clients'] }),
  });

  return (
    <div className="pp">
      <header className="pp__head">
        <div>
          <h1>Clients</h1>
          <p>Manage external client accounts with time-bound access.</p>
        </div>
        <Button onClick={() => setShowNew((v) => !v)}><Plus size={16}/> New client</Button>
      </header>

      {showNew && (
        <div className="pp__create">
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
          <span>Client</span><span>Company</span><span>Access until</span><span>Status</span>
        </div>
        {data?.items.map((u) => (
          <div key={u.id} className="pp__row">
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
            <span className={`pp__status pp__status--${u.status.toLowerCase()}`}>{u.status}</span>
          </div>
        ))}
        {!data?.items.length && <div className="pp__empty">No clients yet.</div>}
      </div>
    </div>
  );
}
