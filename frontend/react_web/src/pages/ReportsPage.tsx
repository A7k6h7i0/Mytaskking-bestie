import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { FileText, MessageSquareReply, Pencil } from 'lucide-react';
import dayjs from 'dayjs';
import { api } from '@/services/api';
import { getSocket } from '@/services/socket';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { useAuthStore } from '@/store/auth';
import { toast } from '@/components/Toast';
import { TaskReportModal, type ReportPerson } from '@/pages/TaskReportModal';
import './reports.css';

type ReportRecipient = {
  id: string;
  userId: string;
  user: ReportPerson;
  responseBody?: string | null;
  respondedAt?: string | null;
  responseUpdatedAt?: string | null;
};

type TaskReport = {
  id: string;
  body: string;
  wordCount: number;
  createdAt: string;
  updatedAt: string;
  task: { id: string; title: string; status: string; priority: string; dueAt?: string | null };
  author: ReportPerson;
  authorId: string;
  recipients: ReportRecipient[];
};

type ReportsData = { mine: TaskReport[]; received: TaskReport[] };

function countWords(value: string) {
  return value.trim().split(/\s+/).filter(Boolean).length;
}

export default function ReportsPage() {
  const qc = useQueryClient();
  const me = useAuthStore((s) => s.user);
  const [tab, setTab] = useState<'mine' | 'received'>('mine');
  const [editing, setEditing] = useState<TaskReport | null>(null);

  const { data, isLoading } = useQuery<ReportsData>({
    queryKey: ['reports.mine'],
    queryFn: async () => (await api.get('/reports')).data,
  });

  useEffect(() => {
    const socket = getSocket();
    if (!socket) return;
    const refresh = () => qc.invalidateQueries({ queryKey: ['reports.mine'] });
    socket.on('task.report.created', refresh);
    socket.on('task.report.updated', refresh);
    socket.on('task.report.response', refresh);
    return () => {
      socket.off('task.report.created', refresh);
      socket.off('task.report.updated', refresh);
      socket.off('task.report.response', refresh);
    };
  }, [qc]);

  const updateReport = useMutation({
    mutationFn: async ({ id, body, recipientIds }: { id: string; body: string; recipientIds: string[] }) =>
      (await api.patch(`/reports/${id}`, { body, recipientIds })).data,
    onSuccess: () => {
      toast.success('Report updated');
      setEditing(null);
      qc.invalidateQueries({ queryKey: ['reports.mine'] });
    },
    onError: () => toast.error('Could not update report'),
  });

  const mine = data?.mine || [];
  const received = data?.received || [];
  const items = tab === 'mine' ? mine : received;

  return (
    <div className="rp">
      <header className="rp__head">
        <div>
          <h1>Reports</h1>
          <p>Completion reports you sent, and reports teammates sent to you.</p>
        </div>
      </header>

      <div className="rp__tabs">
        <button className={tab === 'mine' ? 'is-active' : ''} onClick={() => setTab('mine')}>
          My reports <span>{mine.length}</span>
        </button>
        <button className={tab === 'received' ? 'is-active' : ''} onClick={() => setTab('received')}>
          Reported to me <span>{received.length}</span>
        </button>
      </div>

      {isLoading ? (
        <div className="rp__empty">Loading reports...</div>
      ) : items.length === 0 ? (
        <div className="rp__empty">
          <FileText size={28} />
          <strong>No reports yet</strong>
          <span>{tab === 'mine' ? 'Complete a task to submit your first report.' : 'Reports sent to you will appear here.'}</span>
        </div>
      ) : (
        <div className="rp__list">
          {items.map((report) => (
            <ReportCard
              key={report.id}
              report={report}
              meId={me?.id}
              mode={tab}
              onEdit={() => setEditing(report)}
            />
          ))}
        </div>
      )}

      {editing && (
        <TaskReportModal
          open
          onClose={() => setEditing(null)}
          title="Edit report"
          description="Update your report and who it was sent to."
          initialBody={editing.body}
          initialRecipients={editing.recipients.map((r) => r.user)}
          submitLabel="Save changes"
          busy={updateReport.isPending}
          onSubmit={(body, recipientIds) => updateReport.mutate({ id: editing.id, body, recipientIds })}
        />
      )}
    </div>
  );
}

function ReportCard({
  report,
  meId,
  mode,
  onEdit,
}: {
  report: TaskReport;
  meId?: string;
  mode: 'mine' | 'received';
  onEdit: () => void;
}) {
  const myRecipient = useMemo(
    () => report.recipients.find((recipient) => recipient.userId === meId),
    [report.recipients, meId]
  );
  return (
    <article className="rp__card">
      <div className="rp__card-head">
        <div>
          <Badge tone={report.task.priority === 'URGENT' ? 'danger' : report.task.priority === 'HIGH' ? 'warning' : 'info'} dot>
            {report.task.priority}
          </Badge>
          <h2>{report.task.title}</h2>
          <span>{dayjs(report.createdAt).format('MMM D, YYYY HH:mm')}</span>
        </div>
        {mode === 'mine' && (
          <Button variant="ghost" size="sm" onClick={onEdit}>
            <Pencil size={14} /> Edit
          </Button>
        )}
      </div>

      <div className="rp__thread">
        <div className="rp__bubble rp__bubble--report">
          <div className="rp__person">
            <Avatar name={report.author.name} src={report.author.avatarUrl} isClient={!!report.author.isClient} size={28} />
            <div>
              <UserName name={report.author.name} isClient={!!report.author.isClient} role={report.author.role} />
              <span>Completion report - {report.wordCount}/120 words</span>
            </div>
          </div>
          <p>{report.body}</p>
        </div>

        {report.recipients.map((recipient) => (
          <div key={recipient.id} className="rp__bubble rp__bubble--response">
            <div className="rp__person">
              <Avatar name={recipient.user.name} src={recipient.user.avatarUrl} isClient={!!recipient.user.isClient} size={24} />
              <div>
                <UserName name={recipient.user.name} isClient={!!recipient.user.isClient} role={recipient.user.role} />
                <span>{recipient.responseBody ? `Responded ${dayjs(recipient.responseUpdatedAt || recipient.respondedAt).format('MMM D, HH:mm')}` : 'No response yet'}</span>
              </div>
            </div>
            {recipient.responseBody ? <p>{recipient.responseBody}</p> : <em>Waiting for response.</em>}
          </div>
        ))}

        {mode === 'received' && myRecipient && (
          <ReportResponseBox reportId={report.id} initialBody={myRecipient.responseBody || ''} />
        )}
      </div>
    </article>
  );
}

function ReportResponseBox({ reportId, initialBody }: { reportId: string; initialBody: string }) {
  const qc = useQueryClient();
  const [body, setBody] = useState(initialBody);
  useEffect(() => setBody(initialBody), [initialBody]);

  const response = useMutation({
    mutationFn: async () => (await api.put(`/reports/${reportId}/response`, { body: body.trim() })).data,
    onSuccess: () => {
      toast.success(initialBody ? 'Response updated' : 'Response sent');
      qc.invalidateQueries({ queryKey: ['reports.mine'] });
    },
    onError: () => toast.error('Could not save response'),
  });

  const words = countWords(body);
  const canSubmit = body.trim().length > 0 && words <= 120 && !response.isPending;

  return (
    <div className="rp__response-box">
      <label>
        <MessageSquareReply size={14} />
        Your one-time response
      </label>
      <textarea
        rows={3}
        value={body}
        maxLength={1600}
        placeholder="Send a simple response to this report..."
        onChange={(e) => setBody(e.target.value)}
      />
      <div className="rp__response-foot">
        <span className={words > 120 ? 'is-over' : ''}>{words}/120 words</span>
        <Button size="sm" onClick={() => response.mutate()} disabled={!canSubmit} loading={response.isPending}>
          {initialBody ? 'Update response' : 'Send response'}
        </Button>
      </div>
    </div>
  );
}
