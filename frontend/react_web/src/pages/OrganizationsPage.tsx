import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Building2, Plus, Shield } from 'lucide-react';
import { api } from '@/services/api';
import { toast } from '@/components/Toast';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import './people.css';

type Organisation = {
  id: string;
  slug: string;
  name: string;
  status: 'PENDING' | 'ACTIVE' | 'SUSPENDED';
  userCount?: number;
  createdAt: string;
};

export default function OrganizationsPage() {
  const qc = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [form, setForm] = useState({
    name: '',
    slug: '',
    adminName: '',
    adminUserId: '',
    adminPassword: '',
  });

  const { data, isLoading } = useQuery<{ items: Organisation[] }>({
    queryKey: ['tenants'],
    queryFn: async () => (await api.get('/tenants')).data,
  });

  const createMut = useMutation({
    mutationFn: async () => (await api.post('/tenants', form)).data,
    onSuccess: (result) => {
      qc.invalidateQueries({ queryKey: ['tenants'] });
      setShowNew(false);
      setForm({ name: '', slug: '', adminName: '', adminUserId: '', adminPassword: '' });
      toast.success(
        `Organisation "${result.organisation.name}" created`,
        `Admin login: ${result.organisation.slug} / ${result.admin.userId}`,
      );
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not create organisation'),
  });

  const suspendMut = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: 'ACTIVE' | 'SUSPENDED' }) =>
      (await api.patch(`/tenants/${id}`, { status })).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tenants'] });
      toast.success('Organisation updated');
    },
    onError: () => toast.error('Could not update organisation'),
  });

  const orgs = (data?.items || [])
    .filter((o) => o.slug !== 'default')
    .sort((a, b) => {
      if (a.status === 'PENDING' && b.status !== 'PENDING') return -1;
      if (b.status === 'PENDING' && a.status !== 'PENDING') return 1;
      return 0;
    });

  const pendingCount = orgs.filter((o) => o.status === 'PENDING').length;

  return (
    <div className="pp">
      <header className="pp__head">
        <div>
          <h1 className="pp__title">Organisations</h1>
          <p className="pp__sub">
            Platform view — approve registrations, suspend orgs, or create companies directly.
            {pendingCount > 0 ? ` ${pendingCount} pending approval.` : ''}
          </p>
        </div>
        <Button onClick={() => setShowNew((v) => !v)}>
          <Plus size={16} /> New organisation
        </Button>
      </header>

      {showNew && (
        <section className="pp__card m-fade-up" style={{ marginBottom: 20 }}>
          <h2 className="pp__card-title">Create organisation</h2>
          <div className="pp__form-grid">
            <Input
              label="Company name"
              value={form.name}
              onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
              placeholder="Digital Links"
            />
            <Input
              label="Organisation ID (login slug)"
              value={form.slug}
              onChange={(e) => setForm((f) => ({ ...f, slug: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, '-') }))}
              placeholder="digital-links"
            />
            <Input
              label="Admin full name"
              value={form.adminName}
              onChange={(e) => setForm((f) => ({ ...f, adminName: e.target.value }))}
            />
            <Input
              label="Admin user ID"
              value={form.adminUserId}
              onChange={(e) => setForm((f) => ({ ...f, adminUserId: e.target.value }))}
            />
            <Input
              label="Admin password"
              type="password"
              value={form.adminPassword}
              onChange={(e) => setForm((f) => ({ ...f, adminPassword: e.target.value }))}
            />
          </div>
          <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
            <Button
              disabled={createMut.isPending}
              onClick={() => createMut.mutate()}
            >
              Create organisation
            </Button>
            <Button variant="ghost" onClick={() => setShowNew(false)}>Cancel</Button>
          </div>
        </section>
      )}

      <div className="pp__list">
        {isLoading && <div className="pp__empty">Loading organisations…</div>}
        {!isLoading && orgs.length === 0 && (
          <div className="pp__empty">No customer organisations yet. Create one or wait for self-registration.</div>
        )}
        {orgs.map((org) => (
          <article key={org.id} className="pp__row">
            <div className="pp__row-icon"><Building2 size={18} /></div>
            <div className="pp__row-body">
              <div className="pp__row-title">{org.name}</div>
              <div className="pp__row-meta-line">
                Login slug: <code>{org.slug}</code> · {org.userCount ?? 0} users · {org.status}
              </div>
            </div>
            <div className="pp__row-actions">
              {org.status === 'PENDING' ? (
                <>
                  <Button onClick={() => suspendMut.mutate({ id: org.id, status: 'ACTIVE' })}>
                    Approve
                  </Button>
                  <Button
                    variant="ghost"
                    onClick={() => suspendMut.mutate({ id: org.id, status: 'SUSPENDED' })}
                  >
                    Reject
                  </Button>
                </>
              ) : org.status === 'ACTIVE' ? (
                <Button
                  variant="ghost"
                  onClick={() => suspendMut.mutate({ id: org.id, status: 'SUSPENDED' })}
                >
                  Suspend
                </Button>
              ) : (
                <Button
                  variant="ghost"
                  onClick={() => suspendMut.mutate({ id: org.id, status: 'ACTIVE' })}
                >
                  Activate
                </Button>
              )}
            </div>
          </article>
        ))}
      </div>

      <section className="pp__card" style={{ marginTop: 24 }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <Shield size={18} style={{ marginTop: 2, opacity: 0.7 }} />
          <div>
            <strong>Approvals &amp; privacy</strong>
            <p className="pp__sub" style={{ marginTop: 6 }}>
              Self-registered organisations stay <strong>PENDING</strong> until you approve them.
              Each organisation&apos;s data stays fully isolated after activation.
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
