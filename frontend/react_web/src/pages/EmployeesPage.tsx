import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, Search } from 'lucide-react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import './people.css';

export default function EmployeesPage() {
  const qc = useQueryClient();
  const [q, setQ] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [form, setForm] = useState({ userId: '', password: '', name: '', role: 'EMPLOYEE', email: '' });

  const { data } = useQuery<{ items: any[] }>({
    queryKey: ['employees', q],
    queryFn: async () => (await api.get('/employees', { params: { q } })).data,
  });

  const createMut = useMutation({
    mutationFn: async () => (await api.post('/employees', form)).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['employees'] });
      setShowNew(false);
      setForm({ userId: '', password: '', name: '', role: 'EMPLOYEE', email: '' });
    },
  });

  return (
    <div className="pp">
      <header className="pp__head">
        <div>
          <h1>Employees</h1>
          <p>Manage internal staff, roles, and access.</p>
        </div>
        <Button onClick={() => setShowNew((v) => !v)}><Plus size={16} /> New employee</Button>
      </header>

      {showNew && (
        <div className="pp__create">
          <Input label="User ID" value={form.userId} onChange={(e) => setForm({ ...form, userId: e.target.value })} />
          <Input label="Password" type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
          <Input label="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <Input label="Email (optional)" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          <label className="pp__role">
            <span>Role</span>
            <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
              <option value="ADMIN">Admin</option>
              <option value="EMPLOYEE">Employee</option>
              <option value="TELECALLER">Telecaller</option>
            </select>
          </label>
          <div className="pp__create-actions">
            <Button variant="ghost" onClick={() => setShowNew(false)}>Cancel</Button>
            <Button loading={createMut.isPending} onClick={() => createMut.mutate()}>Create</Button>
          </div>
        </div>
      )}

      <div className="pp__filters">
        <Input leading={<Search size={14} />} placeholder="Search by name, user ID, email" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>

      <div className="pp__table">
        <div className="pp__row pp__row--head">
          <span>Name</span><span>User ID</span><span>Role</span><span>Status</span>
        </div>
        {data?.items.map((u) => (
          <div key={u.id} className="pp__row">
            <span className="pp__name"><Avatar name={u.name} src={u.avatarUrl} size={28} /> {u.name}</span>
            <span className="pp__mono">{u.userId}</span>
            <span><span className="pp__chip">{u.role.replace('_', ' ')}</span></span>
            <span className={`pp__status pp__status--${u.status.toLowerCase()}`}>{u.status}</span>
          </div>
        ))}
        {!data?.items.length && <div className="pp__empty">No employees yet. Add one above.</div>}
      </div>
    </div>
  );
}
