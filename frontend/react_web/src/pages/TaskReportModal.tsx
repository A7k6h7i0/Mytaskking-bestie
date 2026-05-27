import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Users, X } from 'lucide-react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Modal } from '@/components/ui/Modal';
import { Badge } from '@/components/ui/Badge';
import { useAuthStore } from '@/store/auth';
import './tasks.css';
import './reports.css';

export type ReportPerson = {
  id: string;
  userId?: string;
  name: string;
  avatarUrl?: string | null;
  isClient?: boolean;
  role: string;
};

function countWords(value: string) {
  return value.trim().split(/\s+/).filter(Boolean).length;
}

export function TaskReportModal({
  open,
  onClose,
  title,
  description,
  initialBody = '',
  initialRecipients = [],
  submitLabel = 'Submit report',
  busy,
  onSubmit,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  initialBody?: string;
  initialRecipients?: ReportPerson[];
  submitLabel?: string;
  busy?: boolean;
  onSubmit: (body: string, recipientIds: string[]) => void;
}) {
  const me = useAuthStore((s) => s.user);
  const [body, setBody] = useState('');
  const [picked, setPicked] = useState<ReportPerson[]>([]);
  const [peopleQuery, setPeopleQuery] = useState('');

  useEffect(() => {
    if (!open) return;
    setBody(initialBody || '');
    setPicked(initialRecipients);
    setPeopleQuery('');
  }, [open, initialBody, initialRecipients]);

  const { data: peopleData } = useQuery<{ items: ReportPerson[] }>({
    queryKey: ['people.reportable', peopleQuery],
    queryFn: async () => (await api.get('/employees', { params: { q: peopleQuery || undefined } })).data,
    enabled: open,
  });

  const pickedIds = useMemo(() => new Set(picked.map((p) => p.id)), [picked]);
  const candidates = useMemo(
    () => (peopleData?.items || []).filter((p) => !pickedIds.has(p.id)),
    [peopleData, pickedIds]
  );
  const words = countWords(body);
  const canSubmit = body.trim().length > 0 && words <= 120 && picked.length > 0 && !busy;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      description={description || 'Write a short completion report and choose who should receive it.'}
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button onClick={() => onSubmit(body.trim(), picked.map((p) => p.id))} disabled={!canSubmit} loading={busy}>
            {submitLabel}
          </Button>
        </>
      }
    >
      <div className="trm">
        <label className="tk__field">
          <span>Completion report</span>
          <textarea
            rows={5}
            autoFocus
            maxLength={1600}
            placeholder="What did you finish, what changed, and anything the reviewer should know?"
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
          <span className={words > 120 ? 'trm__count is-over' : 'trm__count'}>{words}/120 words</span>
        </label>

        <div className="tk__field">
          <span className="tk__field-label">Report to</span>
          {picked.length > 0 && (
            <div className="tk__chips">
              {picked.map((p) => (
                <button
                  key={p.id}
                  className="tk__chip"
                  type="button"
                  onClick={() => setPicked((prev) => prev.filter((x) => x.id !== p.id))}
                >
                  <Avatar name={p.name} src={p.avatarUrl} isClient={!!p.isClient} size={18} />
                  <UserName name={p.name} isClient={!!p.isClient} role={p.role} />
                  <X size={12} />
                </button>
              ))}
            </div>
          )}
          <Input
            placeholder="Search people..."
            leading={<Users size={14} />}
            value={peopleQuery}
            onChange={(e) => setPeopleQuery(e.target.value)}
          />
          <div className="tk__people">
            {candidates.slice(0, 8).map((p) => (
              <button
                key={p.id}
                type="button"
                className="tk__person"
                onClick={() => {
                  setPicked((prev) => [...prev, p]);
                  setPeopleQuery('');
                }}
              >
                <Avatar name={p.name} src={p.avatarUrl} isClient={!!p.isClient} size={26} />
                <div>
                  <UserName name={p.name} isClient={!!p.isClient} role={p.role} />
                  <span className="tk__person-meta">{p.userId || 'user'} - {p.role.replace(/_/g, ' ')}</span>
                </div>
                {p.id === me?.id && <Badge tone="neutral">You</Badge>}
              </button>
            ))}
            {candidates.length === 0 && <div className="tk__hint">No matching people.</div>}
          </div>
        </div>
      </div>
    </Modal>
  );
}
