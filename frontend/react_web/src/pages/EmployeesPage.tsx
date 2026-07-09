import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Check, MessageSquare, Pencil, Phone, Plus, Search, Siren, Trash2, X } from 'lucide-react';
import { api } from '@/services/api';
import { toast } from '@/components/Toast';
import { useConfirm } from '@/components/ui/ConfirmDialog';
import { useAuthStore } from '@/store/auth';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import './people.css';

const EMPLOYEE_DESIGNATIONS = [
  'Frontend Developer',
  'Backend Developer',
  'Web Developer',
  'Project Manager',
  'Project Coordinator',
  'Employee',
];

export default function EmployeesPage() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { confirm, ConfirmRenderer } = useConfirm();
  const user = useAuthStore((s) => s.user);
  const [q, setQ] = useState('');
  const [showNew, setShowNew] = useState(false);
  const [useCustomDesignation, setUseCustomDesignation] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draftName, setDraftName] = useState('');
  const [draftTitle, setDraftTitle] = useState('');
  const [form, setForm] = useState({ userId: '', password: '', name: '', role: 'EMPLOYEE', customTitle: '', email: '', supervisorIds: [] as string[] });
  const canCustomizeEmployeeName = user?.role === 'SUPER_ADMIN';
  const canManageEmployees =
    user?.role === 'SUPER_ADMIN' || user?.role === 'ADMIN' || user?.role === 'MANAGER';
  const viewerCanCallAdmins = user?.role === 'SUPER_ADMIN' || user?.role === 'ADMIN';
  const passwordTooShort = form.password.length > 0 && form.password.length < 8;
  const selectedDesignation = useCustomDesignation || (form.customTitle && !EMPLOYEE_DESIGNATIONS.includes(form.customTitle)) ? 'CUSTOM' : form.customTitle;

  const { data } = useQuery<{ items: any[] }>({
    queryKey: ['employees', q],
    queryFn: async () => (await api.get('/employees', { params: { q } })).data,
  });

  const createMut = useMutation({
    mutationFn: async () => (await api.post('/employees', form)).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['employees'] });
      setShowNew(false);
      setUseCustomDesignation(false);
      setForm({ userId: '', password: '', name: '', role: 'EMPLOYEE', customTitle: '', email: '', supervisorIds: [] });
      toast.success('Employee created');
    },
    onError: (err: any) => {
      const apiError = err?.response?.data?.error;
      const detail = Array.isArray(apiError?.details) && apiError.details.length ? apiError.details[0] : '';
      toast.error(apiError?.message || 'Could not create employee', detail || 'Please check the form and try again.');
    },
  });

  const startDmMut = useMutation({
    mutationFn: async (targetId: string) => (await api.post('/channels', { kind: 'DM', memberIds: [targetId] })).data,
    onSuccess: (channel) => {
      navigate(`/chat/${channel.id}`);
      toast.success('Direct message ready');
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not start direct message'),
  });

  const startCallMut = useMutation({
    mutationFn: async ({ targetId, targetName }: { targetId: string; targetName: string }) => {
      const result = await api.post('/calls/initiate', { participantIds: [targetId], kind: 'ONE_TO_ONE' });
      return { ...result.data, targetName };
    },
    onSuccess: (result) => {
      if (result.targetPresence) {
        const availability = result.targetPresence.customStatus || result.targetPresence.status || 'unavailable';
        toast.info(`${result.targetName} is unavailable`, availability);
        return;
      }
      toast.success(`Calling ${result.targetName}`, 'Voice room is opening now.');
      navigate(`/calls/live/${result.call.id}`);
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not start call'),
  });

  const emergencyMut = useMutation({
    mutationFn: async ({ targetId }: { targetId: string; targetName: string }) =>
      (await api.post('/emergency/alert', { userId: targetId })).data,
    onSuccess: (_r, vars) => toast.success(`Emergency alert sent to ${vars.targetName}`, 'They will be alerted immediately.'),
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not send emergency alert'),
  });

  const renameMut = useMutation({
    mutationFn: async ({ id, name, customTitle }: { id: string; name: string; customTitle: string }) =>
      (await api.patch(`/employees/${id}`, { name, customTitle })).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['employees'] });
      setEditingId(null);
      setDraftName('');
      setDraftTitle('');
      toast.success('Employee updated');
    },
    onError: (err: any) => toast.error(err?.response?.data?.error?.message || 'Could not update employee name'),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: string) => (await api.delete(`/employees/${id}`)).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['employees'] });
      toast.success('Employee deleted');
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not delete employee'),
  });

  async function askDelete(employee: { id: string; name: string; userId: string; role: string }) {
    if (employee.role === 'SUPER_ADMIN') {
      toast.error('Cannot delete the super admin account');
      return;
    }
    const ok = await confirm({
      title: `Delete ${employee.name}?`,
      description:
        'This permanently removes their account, task assignments, and sign-in access. This cannot be undone.',
      confirmLabel: 'Delete employee',
      variant: 'danger',
      confirmText: employee.userId,
    });
    if (ok) deleteMut.mutate(employee.id);
  }

  const items = useMemo(() => data?.items ?? [], [data?.items]);

  function toggleSupervisor(id: string) {
    setForm((current) => ({
      ...current,
      supervisorIds: current.supervisorIds.includes(id)
        ? current.supervisorIds.filter((item) => item !== id)
        : [...current.supervisorIds, id],
    }));
  }

  return (
    <div className="pp">
      <ConfirmRenderer />
      <header className="pp__head">
        <div>
          <h1>Employees</h1>
          <p>Manage internal staff, roles, and access.</p>
        </div>
        {canManageEmployees && <Button onClick={() => setShowNew((v) => !v)}><Plus size={16} /> New employee</Button>}
      </header>

      {canManageEmployees && showNew && (
        <div className="pp__create">
          <Input label="User ID" value={form.userId} onChange={(e) => setForm({ ...form, userId: e.target.value })} />
          <Input label="Password" type="password" hint={passwordTooShort ? 'Password must be at least 8 characters.' : 'Use at least 8 characters.'} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
          <Input label="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <label className="pp__role">
            <span>Designation / title</span>
            <select
              value={selectedDesignation}
              onChange={(e) => {
                setUseCustomDesignation(e.target.value === 'CUSTOM');
                setForm({ ...form, customTitle: e.target.value === 'CUSTOM' ? '' : e.target.value });
              }}
            >
              <option value="">Select employee designation</option>
              {EMPLOYEE_DESIGNATIONS.map((designation) => (
                <option key={designation} value={designation}>{designation}</option>
              ))}
              <option value="CUSTOM">Custom designation</option>
            </select>
          </label>
          {selectedDesignation === 'CUSTOM' && (
            <Input label="Custom designation (optional)" hint="Examples: Flutter Developer, MD, Director" value={form.customTitle} onChange={(e) => setForm({ ...form, customTitle: e.target.value })} />
          )}
          <Input label="Email (optional)" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          <label className="pp__role">
            <span>Access role</span>
            <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
              <option value="ADMIN">Admin</option>
              <option value="MANAGER">Manager</option>
              <option value="PROJECT_COORDINATOR_MANAGER">Project Coordinating Manager</option>
              <option value="EMPLOYEE">Employee</option>
              <option value="TELECALLER">Telecaller</option>
            </select>
          </label>
          <div className="pp__supervisors">
            <span>Supervisors for notifications</span>
            <div className="pp__supervisor-list">
              {items
                .filter((entry) => entry.id !== form.userId && entry.status === 'ACTIVE')
                .slice(0, 10)
                .map((entry) => (
                  <button type="button" key={entry.id} className={`pp__supervisor-chip ${form.supervisorIds.includes(entry.id) ? 'is-selected' : ''}`} onClick={() => toggleSupervisor(entry.id)}>
                    <Avatar name={entry.name} src={entry.avatarUrl} size={18} />
                    <span>{entry.name}</span>
                  </button>
                ))}
              {!items.length && <span className="pp__supervisor-empty">Create or search employees first to map supervisors.</span>}
            </div>
          </div>
          <div className="pp__create-actions">
            <Button variant="ghost" onClick={() => setShowNew(false)}>Cancel</Button>
            <Button loading={createMut.isPending} disabled={!form.userId.trim() || !form.name.trim() || !form.password || passwordTooShort} onClick={() => createMut.mutate()}>Create</Button>
          </div>
        </div>
      )}

      <div className="pp__filters">
        <Input leading={<Search size={14} />} placeholder="Search by name, user ID, email" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>

      <div className="pp__table">
        <div className="pp__row pp__row--head">
          <span>Name</span><span>User ID</span><span>Role</span><span>Status</span><span>Actions</span>
        </div>
        {items.map((u) => {
          const isEditing = editingId === u.id;
          return (
            <div key={u.id} className="pp__row">
              <span className="pp__name">
                <Avatar name={u.name} src={u.avatarUrl} size={28} />
                {isEditing ? (
                  <input
                    className="pp__inline-input"
                    value={draftName}
                    onChange={(e) => setDraftName(e.target.value)}
                    placeholder="Employee display name"
                    maxLength={120}
                  />
                ) : (
                  u.name
                )}
              </span>
              <span className="pp__mono">{u.userId}</span>
              <span>
                {isEditing ? (
                  <input
                    className="pp__inline-input"
                    value={draftTitle}
                    onChange={(e) => setDraftTitle(e.target.value)}
                    placeholder="e.g. Flutter Developer"
                    maxLength={120}
                  />
                ) : (
                  <span className="pp__chip">{u.customTitle || u.role.replace(/_/g, ' ')}</span>
                )}
              </span>
              <span className={`pp__status pp__status--${u.status.toLowerCase()}`}>{u.status}</span>
              <span className="pp__actions">
                {u.role !== 'SUPER_ADMIN' && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => startDmMut.mutate(u.id)}
                    disabled={startDmMut.isPending || u.id === user?.id}
                  >
                    <MessageSquare size={14} /> Message
                  </Button>
                )}
                {(viewerCanCallAdmins || (u.role !== 'ADMIN' && u.role !== 'SUPER_ADMIN')) && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => startCallMut.mutate({ targetId: u.id, targetName: u.name })}
                    disabled={startCallMut.isPending || u.id === user?.id}
                  >
                    <Phone size={14} /> Call
                  </Button>
                )}
                {canManageEmployees && u.id !== user?.id && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      if (window.confirm(`Send an emergency siren alert to ${u.name}? Use this only for urgent escalations.`)) {
                        emergencyMut.mutate({ targetId: u.id, targetName: u.name });
                      }
                    }}
                    disabled={emergencyMut.isPending}
                    title="Emergency siren alert"
                  >
                    <Siren size={14} /> Emergency
                  </Button>
                )}
                {canCustomizeEmployeeName && (
                  isEditing ? (
                    <>
                      <Button
                        size="sm"
                        onClick={() => renameMut.mutate({ id: u.id, name: draftName.trim(), customTitle: draftTitle.trim() })}
                        loading={renameMut.isPending}
                        disabled={!draftName.trim() || (draftName.trim() === u.name && draftTitle.trim() === (u.customTitle || ''))}
                      >
                        <Check size={14} /> Save
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => { setEditingId(null); setDraftName(''); setDraftTitle(''); }}
                      >
                        <X size={14} /> Cancel
                      </Button>
                    </>
                  ) : (
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => { setEditingId(u.id); setDraftName(u.name); setDraftTitle(u.customTitle || ''); }}
                    >
                      <Pencil size={14} /> Edit
                    </Button>
                  )
                )}
                {canManageEmployees && u.id !== user?.id && u.role !== 'SUPER_ADMIN' && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => askDelete(u)}
                    disabled={deleteMut.isPending}
                    title="Delete employee permanently"
                  >
                    <Trash2 size={14} /> Delete
                  </Button>
                )}
              </span>
            </div>
          );
        })}
        {!items.length && <div className="pp__empty">No employees yet. Add one above.</div>}
      </div>
    </div>
  );
}
