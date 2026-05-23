import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ShieldCheck, Plus, Trash2 } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Skeleton } from '@/components/ui/Skeleton';
import { toast } from '@/components/Toast';
import './permissions.css';

type Grant = {
  id: string;
  userId: string | null;
  roleName: string | null;
  key: string;
  allow: boolean;
  scope: unknown;
  createdAt: string;
};

const ROLES = ['SUPER_ADMIN', 'ADMIN', 'MANAGER', 'PROJECT_COORDINATOR_MANAGER', 'EMPLOYEE', 'TELECALLER', 'CLIENT'];
const COMMON_KEYS = [
  'task.delete', 'task.assign_others',
  'channel.manage', 'channel.delete',
  'call.record', 'call.transfer',
  'file.view_client', 'file.share_external',
  'analytics.view', 'audit.view',
];

export default function PermissionsPage() {
  const qc = useQueryClient();
  const [form, setForm] = useState({ roleName: 'EMPLOYEE', key: 'task.delete', allow: true });

  const { data, isLoading } = useQuery<{ items: Grant[] }>({
    queryKey: ['permissions.grants'],
    queryFn: async () => (await api.get('/permissions/grants')).data,
  });

  const grantMut = useMutation({
    mutationFn: async () => (await api.post('/permissions/grants', { roleName: form.roleName, key: form.key, allow: form.allow })).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['permissions.grants'] });
      toast.success('Grant saved');
    },
    onError: () => toast.error('Could not save grant'),
  });

  const revokeMut = useMutation({
    mutationFn: async (id: string) => (await api.delete(`/permissions/grants/${id}`)).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['permissions.grants'] }),
  });

  return (
    <div className="pm">
      <header className="pm__head">
        <div>
          <h1>Permissions</h1>
          <p>Role-level + per-user grants on top of the default RBAC matrix. Explicit denies always win.</p>
        </div>
      </header>

      <section className="pm__compose">
        <h3>Grant a permission</h3>
        <div className="pm__compose-grid">
          <label className="pm__select">
            <span>Role</span>
            <select value={form.roleName} onChange={(e) => setForm({ ...form, roleName: e.target.value })}>
              {ROLES.map((r) => <option key={r} value={r}>{r.replace('_', ' ')}</option>)}
            </select>
          </label>
          <label className="pm__select">
            <span>Permission key</span>
            <select value={form.key} onChange={(e) => setForm({ ...form, key: e.target.value })}>
              {COMMON_KEYS.map((k) => <option key={k} value={k}>{k}</option>)}
            </select>
          </label>
          <Input
            label="Custom key (overrides dropdown)"
            placeholder="some.new.key"
            value={form.key}
            onChange={(e) => setForm({ ...form, key: e.target.value })}
          />
          <label className="pm__select">
            <span>Effect</span>
            <select value={form.allow ? 'allow' : 'deny'} onChange={(e) => setForm({ ...form, allow: e.target.value === 'allow' })}>
              <option value="allow">Allow</option>
              <option value="deny">Deny</option>
            </select>
          </label>
          <Button onClick={() => grantMut.mutate()} loading={grantMut.isPending}><Plus size={14}/> Grant</Button>
        </div>
      </section>

      <section className="pm__list">
        <h3>Active grants</h3>
        {isLoading && <Skeleton height={120} />}
        {!isLoading && (data?.items.length ?? 0) === 0 && (
          <div className="pm__empty">
            <ShieldCheck size={20}/> No explicit grants — only the baked-in role defaults are in effect.
          </div>
        )}
        {!isLoading && data?.items.map((g) => (
          <div key={g.id} className="pm__row">
            <span className={clsx('pm__chip', g.allow ? 'is-allow' : 'is-deny')}>{g.allow ? 'ALLOW' : 'DENY'}</span>
            <code className="pm__key">{g.key}</code>
            <span className="pm__target">
              {g.roleName && <span className="pm__role">role · {g.roleName.replace('_', ' ')}</span>}
              {g.userId && <span className="pm__user">user · {g.userId.slice(0, 10)}…</span>}
            </span>
            <button className="pm__delete" title="Revoke" onClick={() => revokeMut.mutate(g.id)}>
              <Trash2 size={14}/>
            </button>
          </div>
        ))}
      </section>
    </div>
  );
}
