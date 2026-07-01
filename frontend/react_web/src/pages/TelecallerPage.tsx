import { type FormEvent, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Download, Phone, Plus, Search } from 'lucide-react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { toast } from '@/components/Toast';
import { useAuthStore } from '@/store/auth';
import './telecaller.css';

type Lead = {
  id: string; name: string; phone: string; company?: string | null;
  status: string; nextFollowAt?: string | null; notes?: string | null;
  owner?: { name: string; avatarUrl?: string | null } | null;
};

const LEAD_STATUSES = ['NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'] as const;

export default function TelecallerPage() {
  const qc = useQueryClient();
  const user = useAuthStore((s) => s.user);
  const canDownloadReports = user?.role === 'ADMIN' || user?.role === 'SUPER_ADMIN';
  const downloadsAllReports =
    user?.role === 'SUPER_ADMIN' &&
    (!user.tenant?.slug || user.tenant.slug === 'default' || user.tenantId === 'default');
  const [q, setQ] = useState('');
  const [selected, setSelected] = useState<Lead | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({
    name: '',
    phone: '',
    company: '',
    email: '',
    source: '',
    notes: '',
  });

  const { data } = useQuery<{ items: Lead[] }>({
    queryKey: ['telecaller.leads', q],
    queryFn: async () => (await api.get('/telecaller/leads', { params: { q } })).data,
  });

  const callMut = useMutation({
    mutationFn: async (leadId: string) => (await api.post(`/telecaller/leads/${leadId}/call`)).data,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['telecaller.leads'] }),
  });

  const createMut = useMutation({
    mutationFn: async () => {
      const payload = {
        name: form.name.trim(),
        phone: form.phone.trim(),
        company: form.company.trim() || null,
        email: form.email.trim() || null,
        status: 'NEW',
        source: form.source.trim() || null,
        notes: form.notes.trim() || null,
      };
      return (await api.post('/telecaller/leads', payload)).data as Lead;
    },
    onSuccess: (lead) => {
      toast.success('Lead created');
      setShowCreate(false);
      setSelected(lead);
      setForm({ name: '', phone: '', company: '', email: '', source: '', notes: '' });
      qc.invalidateQueries({ queryKey: ['telecaller.leads'] });
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.error?.message || 'Could not create lead');
    },
  });

  const statusMut = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) =>
      (await api.patch(`/telecaller/leads/${id}`, { status })).data as Lead,
    onSuccess: (lead) => {
      setSelected(lead);
      toast.success('Lead status updated');
      qc.invalidateQueries({ queryKey: ['telecaller.leads'] });
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.error?.message || 'Could not update lead status');
    },
  });

  function updateForm(key: keyof typeof form, value: string) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function submitLead(e: FormEvent) {
    e.preventDefault();
    if (!form.name.trim() || !form.phone.trim()) {
      toast.error('Name and phone are required');
      return;
    }
    createMut.mutate();
  }

  async function downloadDailyReport() {
    try {
      const today = new Date();
      const date = today.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
      const response = await api.get('/telecaller/calls/daily-report.xlsx', {
        params: { date, scope: downloadsAllReports ? 'all' : 'org' },
        responseType: 'blob',
      });
      const blob = new Blob([response.data], {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = downloadsAllReports
        ? `telecaller-calls-all-organisations-${date}.xlsx`
        : `telecaller-calls-${date}.xlsx`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
      toast.success('Report downloaded');
    } catch (err: any) {
      toast.error(err?.response?.data?.error?.message || 'Could not download report');
    }
  }

  return (
    <div className="tc">
      <aside className="tc__list">
        <header className="tc__list-head">
          <h2>Leads</h2>
          <div className="tc__head-actions">
            {canDownloadReports && (
              <Button size="sm" variant="ghost" onClick={downloadDailyReport}><Download size={14}/> Report</Button>
            )}
            <Button size="sm" variant="secondary" onClick={() => setShowCreate(true)}><Plus size={14}/> Add lead</Button>
          </div>
        </header>
        <div className="tc__search">
          <Input leading={<Search size={14} />} placeholder="Search by name, phone, company" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        <ul>
          {data?.items.map((l) => (
            <li key={l.id} className={selected?.id === l.id ? 'is-active' : ''} onClick={() => setSelected(l)}>
              <Avatar name={l.name} size={32} />
              <div className="tc__lead-text">
                <div className="tc__lead-name">{l.name}</div>
                <div className="tc__lead-meta">{l.company || l.phone}</div>
              </div>
              <span className={`tc__status tc__status--${l.status.toLowerCase()}`}>{l.status}</span>
            </li>
          ))}
          {!data?.items.length && <li className="tc__empty">No leads. Add one to get started.</li>}
        </ul>
      </aside>

      <section className="tc__panel">
        {selected ? (
          <>
            <header className="tc__panel-head">
              <div>
                <h2>{selected.name}</h2>
                <p>{selected.company} · {selected.phone}</p>
              </div>
              <Button onClick={() => callMut.mutate(selected.id)} loading={callMut.isPending}>
                <Phone size={16}/> Click to call
              </Button>
            </header>

            <div className="tc__details">
              <div className="tc__detail">
                <label>Status</label>
                <select
                  className="tc__status-select"
                  value={selected.status}
                  disabled={statusMut.isPending}
                  onChange={(e) => statusMut.mutate({ id: selected.id, status: e.target.value })}
                >
                  {LEAD_STATUSES.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              </div>
              <div className="tc__detail">
                <label>Next follow up</label>
                <div>{selected.nextFollowAt ? new Date(selected.nextFollowAt).toLocaleString() : '—'}</div>
              </div>
              <div className="tc__detail tc__detail--full">
                <label>Notes</label>
                <div>{selected.notes || 'No notes yet.'}</div>
              </div>
            </div>
          </>
        ) : (
          <div className="tc__empty-center">Select a lead to see details.</div>
        )}
      </section>

      {showCreate && (
        <div className="tc__modal-backdrop" onMouseDown={() => setShowCreate(false)}>
          <form className="tc__modal" onSubmit={submitLead} onMouseDown={(e) => e.stopPropagation()}>
            <header className="tc__modal-head">
              <div>
                <h3>Add lead</h3>
                <p>Create a lead for Lakshmiraj telecalling workflow.</p>
              </div>
            </header>
            <div className="tc__form-grid">
              <Input label="Lead name *" value={form.name} onChange={(e) => updateForm('name', e.target.value)} autoFocus />
              <Input label="Phone *" value={form.phone} onChange={(e) => updateForm('phone', e.target.value)} />
              <Input label="Company" value={form.company} onChange={(e) => updateForm('company', e.target.value)} />
              <Input label="Email" type="email" value={form.email} onChange={(e) => updateForm('email', e.target.value)} />
              <Input label="Source" value={form.source} onChange={(e) => updateForm('source', e.target.value)} />
              <label className="tc__textarea">
                <span>Notes</span>
                <textarea value={form.notes} onChange={(e) => updateForm('notes', e.target.value)} rows={4} />
              </label>
            </div>
            <footer className="tc__modal-actions">
              <Button type="button" variant="ghost" onClick={() => setShowCreate(false)}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending}>Create lead</Button>
            </footer>
          </form>
        </div>
      )}
    </div>
  );
}
