import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Copy } from 'lucide-react';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { toast } from '@/components/Toast';
import './support-tickets.css';

type IssueType = { value: string; label: string };
type MyTicket = {
  ticketNumber: string;
  issueTypeLabel?: string;
  status?: string;
  statusLabel?: string;
};

async function copyText(value: string) {
  try {
    await navigator.clipboard.writeText(value);
    toast.success('Reference number copied');
  } catch {
    toast.error('Could not copy');
  }
}

export default function ReportProblemPage() {
  const qc = useQueryClient();
  const [tab, setTab] = useState<'report' | 'status'>('report');
  const [issueType, setIssueType] = useState('');
  const [description, setDescription] = useState('');
  const [createdId, setCreatedId] = useState<string | null>(null);
  const [selectedTicket, setSelectedTicket] = useState('');

  const { data: meta } = useQuery<{ issueTypes: IssueType[] }>({
    queryKey: ['support-tickets.meta'],
    queryFn: async () => (await api.get('/support-tickets/meta')).data,
  });

  const { data: mine } = useQuery<{ items: MyTicket[] }>({
    queryKey: ['support-tickets.mine'],
    queryFn: async () => (await api.get('/support-tickets/mine')).data,
  });

  const issueTypes = meta?.issueTypes ?? [];
  const myTickets = mine?.items ?? [];
  const selectedType = issueType || issueTypes[0]?.value || '';
  const activeTicket = selectedTicket || myTickets[0]?.ticketNumber || '';

  const createMut = useMutation({
    mutationFn: async () =>
      (await api.post('/support-tickets', {
        issueType: selectedType,
        description: description.trim(),
      })).data,
    onSuccess: (ticket) => {
      setCreatedId(ticket.ticketNumber);
      setSelectedTicket(ticket.ticketNumber);
      setDescription('');
      qc.invalidateQueries({ queryKey: ['support-tickets.mine'] });
      toast.success('Issue submitted', `Reference: ${ticket.ticketNumber}`);
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not submit issue'),
  });

  const statusMut = useMutation({
    mutationFn: async (ticketNumber: string) =>
      (await api.get('/support-tickets/check-status', {
        params: { ticketNumber: ticketNumber.trim() },
      })).data,
  });

  return (
    <div className="stt">
      <header className="stt__head">
        <div>
          <h1>Report a problem</h1>
          <p>Submit an issue or check progress using your reference numbers.</p>
        </div>
      </header>

      <div className="stt__tabs">
        <button
          type="button"
          className={tab === 'report' ? 'stt__tab stt__tab--active' : 'stt__tab'}
          onClick={() => setTab('report')}
        >
          Report
        </button>
        <button
          type="button"
          className={tab === 'status' ? 'stt__tab stt__tab--active' : 'stt__tab'}
          onClick={() => setTab('status')}
        >
          Check problem
        </button>
      </div>

      {tab === 'report' ? (
        <section className="stt__panel">
          <label className="stt__label">
            Issue type
            <select
              className="stt__select"
              value={selectedType}
              onChange={(e) => setIssueType(e.target.value)}
            >
              {issueTypes.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </label>
          <label className="stt__label">
            Description
            <textarea
              className="stt__textarea"
              rows={6}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What happened? Include steps if you can."
            />
          </label>
          <Button
            onClick={() => createMut.mutate()}
            loading={createMut.isPending}
            disabled={description.trim().length < 10}
          >
            Submit issue
          </Button>
          {createdId && (
            <div className="stt__ticket-card">
              <strong>Reference number</strong>
              <div className="stt__copy-row">
                <p className="stt__ticket-id">{createdId}</p>
                <button type="button" className="stt__copy-btn" onClick={() => copyText(createdId)}>
                  <Copy size={16} /> Copy
                </button>
              </div>
              <p className="stt__subtle">Find this again in Check problem or copy it now.</p>
            </div>
          )}
          {myTickets.length > 0 && (
            <div className="stt__mine-list">
              <h3>Your reference numbers</h3>
              {myTickets.map((t) => (
                <div key={t.ticketNumber} className="stt__mine-item">
                  <div>
                    <strong>{t.ticketNumber}</strong>
                    <p className="stt__subtle">
                      {[t.issueTypeLabel, t.statusLabel || t.status].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  <button type="button" className="stt__copy-btn" onClick={() => copyText(t.ticketNumber)}>
                    <Copy size={16} />
                  </button>
                </div>
              ))}
            </div>
          )}
        </section>
      ) : (
        <section className="stt__panel">
          {myTickets.length === 0 ? (
            <p className="stt__subtle">No reported issues yet. Submit one on the Report tab.</p>
          ) : (
            <>
              <label className="stt__label">
                Reference number
                <select
                  className="stt__select"
                  value={activeTicket}
                  onChange={(e) => {
                    setSelectedTicket(e.target.value);
                    statusMut.reset();
                  }}
                >
                  {myTickets.map((t) => (
                    <option key={t.ticketNumber} value={t.ticketNumber}>
                      {t.ticketNumber} · {t.statusLabel || t.status}
                    </option>
                  ))}
                </select>
              </label>
              {activeTicket && (
                <div className="stt__copy-row stt__copy-row--inline">
                  <span className="stt__ticket-id">{activeTicket}</span>
                  <button type="button" className="stt__copy-btn" onClick={() => copyText(activeTicket)}>
                    <Copy size={16} /> Copy
                  </button>
                </div>
              )}
              <Button
                onClick={() => statusMut.mutate(activeTicket)}
                loading={statusMut.isPending}
                disabled={!activeTicket}
              >
                Check problem
              </Button>
            </>
          )}
          {statusMut.data && (
            <div className="stt__ticket-card">
              <div className="stt__ticket-head">
                <strong>{statusMut.data.ticketNumber}</strong>
                <span className={`stt__badge stt__badge--${String(statusMut.data.status).toLowerCase()}`}>
                  {statusMut.data.statusLabel || statusMut.data.status}
                </span>
              </div>
              <p>{statusMut.data.issueTypeLabel}</p>
              {statusMut.data.assignee?.name && (
                <p className="stt__subtle">Assigned to: {statusMut.data.assignee.name}</p>
              )}
              {statusMut.data.resolutionNotes && (
                <p className="stt__notes">{statusMut.data.resolutionNotes}</p>
              )}
            </div>
          )}
          {statusMut.isError && (
            <p className="stt__error">Could not load this issue.</p>
          )}
        </section>
      )}
    </div>
  );
}
