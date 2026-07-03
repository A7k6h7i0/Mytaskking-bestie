import { type FormEvent, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Download, Phone, Plus, Search, Upload } from 'lucide-react';
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

type Employee = {
  id: string;
  userId: string;
  name: string;
  role: string;
};

const LEAD_STATUSES = ['NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'] as const;

function todayLabel() {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
}

export default function TelecallerPage() {
  const qc = useQueryClient();
  const user = useAuthStore((s) => s.user);
  const canDownloadReports = user?.role === 'ADMIN' || user?.role === 'SUPER_ADMIN';
  const canManageLeads = user?.role === 'ADMIN' || user?.role === 'SUPER_ADMIN';
  const downloadsAllReports =
    user?.role === 'SUPER_ADMIN' &&
    (!user.tenant?.slug || user.tenant.slug === 'default' || user.tenantId === 'default');
  const [q, setQ] = useState('');
  const [selected, setSelected] = useState<Lead | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [showBulkAssign, setShowBulkAssign] = useState(false);
  const [selectedTelecallerIds, setSelectedTelecallerIds] = useState<string[]>([]);
  const [bulkFile, setBulkFile] = useState<File | null>(null);
  const [bulkRows, setBulkRows] = useState('');
  const [bulkForm, setBulkForm] = useState({
    startDate: todayLabel(),
    endDate: todayLabel(),
    recordsPerTelecallerPerDay: '100',
    source: 'admin-upload',
  });
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

  const { data: telecallersData } = useQuery<{ items: Employee[] }>({
    queryKey: ['employees.telecallers'],
    queryFn: async () =>
      (await api.get('/employees', { params: { role: 'TELECALLER', pageSize: 100 } })).data,
    enabled: canManageLeads,
  });
  const telecallers = telecallersData?.items ?? [];

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

  const bulkAssignMut = useMutation({
    mutationFn: async () => {
      if (bulkFile) {
        const form = new FormData();
        form.append('file', bulkFile);
        form.append('telecallerIds', selectedTelecallerIds.join(','));
        form.append('startDate', bulkForm.startDate);
        form.append('endDate', bulkForm.endDate);
        form.append('recordsPerTelecallerPerDay', bulkForm.recordsPerTelecallerPerDay || '100');
        if (bulkForm.source.trim()) form.append('source', bulkForm.source.trim());
        return (await api.post('/telecaller/leads/bulk-distribute-file', form)).data as {
          assigned: number;
          skipped: number;
          telecallers: number;
          workingDays: number;
        };
      }
      const records = parseBulkRows();
      return (await api.post('/telecaller/leads/bulk-distribute', {
        telecallerIds: selectedTelecallerIds,
        startDate: bulkForm.startDate,
        endDate: bulkForm.endDate,
        recordsPerTelecallerPerDay: Number(bulkForm.recordsPerTelecallerPerDay || 100),
        source: bulkForm.source.trim() || null,
        records,
      })).data as {
        assigned: number;
        skipped: number;
        telecallers: number;
        workingDays: number;
      };
    },
    onSuccess: (result) => {
      toast.success(
        `Assigned ${result.assigned} leads to ${result.telecallers} telecaller(s) across ${result.workingDays} working day(s)`,
      );
      setShowBulkAssign(false);
      setBulkRows('');
      setBulkFile(null);
      setSelectedTelecallerIds([]);
      qc.invalidateQueries({ queryKey: ['telecaller.leads'] });
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.error?.message || err?.message || 'Could not assign leads');
    },
  });

  function updateForm(key: keyof typeof form, value: string) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function updateBulkForm(key: keyof typeof bulkForm, value: string) {
    setBulkForm((prev) => ({ ...prev, [key]: value }));
  }

  function toggleTelecaller(id: string) {
    setSelectedTelecallerIds((prev) =>
      prev.includes(id) ? prev.filter((value) => value !== id) : [...prev, id],
    );
  }

  function parseBulkRows() {
    if (!selectedTelecallerIds.length) {
      throw new Error('Select at least one telecaller');
    }
    const lines = bulkRows
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    const dataLines = lines[0]?.toLowerCase().includes('phone') ? lines.slice(1) : lines;
    const records = dataLines.map((line) => {
      const [name = '', phone = '', company = '', email = '', ...notes] =
        line.split(',').map((part) => part.trim());
      return {
        name,
        phone,
        company: company || null,
        email: email || null,
        notes: notes.join(', ').trim() || null,
      };
    });
    const invalid = records.find((record) => !record.name || !record.phone);
    if (!records.length || invalid) {
      throw new Error('Paste rows as: name, phone, company, email, notes');
    }
    return records;
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
            {canManageLeads && (
              <Button size="sm" variant="ghost" onClick={() => setShowBulkAssign(true)}><Upload size={14}/> Bulk assign</Button>
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
                <p>Create a lead for this organisation's telecalling workflow.</p>
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

      {showBulkAssign && (
        <div className="tc__modal-backdrop" onMouseDown={() => setShowBulkAssign(false)}>
          <form
            className="tc__modal tc__modal--wide"
            onSubmit={(e) => {
              e.preventDefault();
              bulkAssignMut.mutate();
            }}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <header className="tc__modal-head">
              <div>
                <h3>Bulk assign leads</h3>
                <p>Paste customer rows and distribute them date-wise to selected telecallers.</p>
              </div>
            </header>

            <div className="tc__form-grid">
              <Input
                label="Start date"
                type="date"
                value={bulkForm.startDate}
                onChange={(e) => updateBulkForm('startDate', e.target.value)}
              />
              <Input
                label="End date"
                type="date"
                value={bulkForm.endDate}
                onChange={(e) => updateBulkForm('endDate', e.target.value)}
              />
              <Input
                label="Records per telecaller per day"
                type="number"
                min="1"
                max="500"
                value={bulkForm.recordsPerTelecallerPerDay}
                onChange={(e) => updateBulkForm('recordsPerTelecallerPerDay', e.target.value)}
              />
              <Input
                label="Source"
                value={bulkForm.source}
                onChange={(e) => updateBulkForm('source', e.target.value)}
              />
            </div>

            <div className="tc__bulk-section">
              <div className="tc__bulk-title">Telecallers</div>
              <div className="tc__telecaller-grid">
                {telecallers.map((person) => (
                  <label key={person.id} className="tc__check">
                    <input
                      type="checkbox"
                      checked={selectedTelecallerIds.includes(person.id)}
                      onChange={() => toggleTelecaller(person.id)}
                    />
                    <span>{person.name || person.userId}</span>
                  </label>
                ))}
                {!telecallers.length && (
                  <div className="tc__helper">No TELECALLER users found. Create them from Employees first.</div>
                )}
              </div>
            </div>

            <label className="tc__file">
              <span>Excel / CSV file</span>
              <input
                type="file"
                accept=".xlsx,.xlsm,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel.sheet.macroEnabled.12,text/csv"
                onChange={(e) => setBulkFile(e.target.files?.[0] ?? null)}
              />
              <small>{bulkFile ? bulkFile.name : 'Upload .xlsx/.xlsm/.csv columns: name, phone, company, email, notes'}</small>
            </label>

            <label className="tc__textarea tc__textarea--bulk">
              <span>Customer data</span>
              <textarea
                value={bulkRows}
                onChange={(e) => setBulkRows(e.target.value)}
                rows={10}
                disabled={!!bulkFile}
                placeholder={'name, phone, company, email, notes\nRavi Kumar, 9876543210, ABC Traders, ravi@example.com, interested in demo'}
              />
            </label>
            <p className="tc__helper">
              Upload Excel/CSV or paste rows manually. The system assigns up to 100 records per selected telecaller for each working day.
            </p>

            <footer className="tc__modal-actions">
              <Button type="button" variant="ghost" onClick={() => setShowBulkAssign(false)}>Cancel</Button>
              <Button type="submit" loading={bulkAssignMut.isPending}>Assign leads</Button>
            </footer>
          </form>
        </div>
      )}
    </div>
  );
}
