import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { UserName } from '@/components/ui/UserName';
import { toast } from '@/components/Toast';
import './leave-approvals.css';

type LeaveRow = {
  id: string;
  leaveType: string;
  fromDate: string;
  toDate?: string | null;
  startTime?: string | null;
  endTime?: string | null;
  description: string;
  user: { id: string; name: string; role?: string; avatarUrl?: string | null };
};

export default function LeaveApprovalsPage() {
  const qc = useQueryClient();

  const { data: items = [], isLoading } = useQuery<LeaveRow[]>({
    queryKey: ['org-leaves.pending'],
    queryFn: async () => (await api.get('/employee-tracking/leaves', { params: { status: 'PENDING' } })).data.items,
  });

  const approve = useMutation({
    mutationFn: (id: string) => api.patch(`/employee-tracking/leaves/${id}/approve`),
    onSuccess: () => {
      toast.success('Leave approved');
      qc.invalidateQueries({ queryKey: ['org-leaves.pending'] });
    },
    onError: () => toast.error('Could not approve leave'),
  });

  const reject = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason?: string }) =>
      api.patch(`/employee-tracking/leaves/${id}/reject`, { reason }),
    onSuccess: () => {
      toast.success('Leave rejected');
      qc.invalidateQueries({ queryKey: ['org-leaves.pending'] });
    },
    onError: () => toast.error('Could not reject leave'),
  });

  return (
    <div className="la-approvals">
      <header>
        <h1>Leave requests</h1>
        <p>Review and approve organisation leave. Approved leave pauses employee GPS tracking.</p>
      </header>

      {isLoading ? (
        <p className="la-approvals__empty">Loading…</p>
      ) : !items.length ? (
        <p className="la-approvals__empty">No pending leave requests.</p>
      ) : (
        <div className="la-approvals__list">
          {items.map((row) => (
            <article key={row.id} className="la-approvals__card">
              <div className="la-approvals__user">
                <Avatar name={row.user.name} src={row.user.avatarUrl} size={36} />
                <div>
                  <UserName name={row.user.name} role={row.user.role} />
                  <span>{row.leaveType.replace('_', ' ')}</span>
                </div>
              </div>
              <p className="la-approvals__dates">
                {row.fromDate}{row.toDate ? ` → ${row.toDate}` : ''}
                {row.startTime ? ` · ${row.startTime}-${row.endTime || ''}` : ''}
              </p>
              <p>{row.description}</p>
              <div className="la-approvals__actions">
                <button
                  type="button"
                  className="la-approvals__reject"
                  onClick={() => {
                    const reason = window.prompt('Rejection reason (optional)') || undefined;
                    reject.mutate({ id: row.id, reason });
                  }}
                >
                  Reject
                </button>
                <button
                  type="button"
                  className="la-approvals__approve"
                  onClick={() => approve.mutate(row.id)}
                >
                  Approve
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
