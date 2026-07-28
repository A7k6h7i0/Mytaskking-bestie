import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Search } from 'lucide-react';
import { useMemo, useState } from 'react';
import { api } from '@/services/api';
import { Avatar } from '@/components/ui/Avatar';
import { Badge } from '@/components/ui/Badge';
import { Input } from '@/components/ui/Input';
import { UserName } from '@/components/ui/UserName';
import { toast } from '@/components/Toast';
import './leave-approvals.css';

type LeaveStatus = 'PENDING' | 'APPROVED' | 'REJECTED';
type StatusFilter = 'ALL' | LeaveStatus;

type LeaveRow = {
  id: string;
  leaveType: string;
  fromDate: string;
  toDate?: string | null;
  startTime?: string | null;
  endTime?: string | null;
  description: string;
  status: LeaveStatus;
  approvedAt?: string | null;
  rejectionReason?: string | null;
  user: { id: string; name: string; role?: string; avatarUrl?: string | null };
};

const STATUS_FILTERS: { value: StatusFilter; label: string }[] = [
  { value: 'ALL', label: 'All' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'APPROVED', label: 'Approved' },
  { value: 'REJECTED', label: 'Rejected' },
];

function leaveTypeLabel(type: string) {
  return type.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
}

function statusTone(status: LeaveStatus) {
  switch (status) {
    case 'APPROVED':
      return 'success' as const;
    case 'REJECTED':
      return 'danger' as const;
    default:
      return 'warning' as const;
  }
}

function statusLabel(status: LeaveStatus) {
  switch (status) {
    case 'APPROVED':
      return 'Approved';
    case 'REJECTED':
      return 'Rejected';
    default:
      return 'Pending';
  }
}

function formatDates(row: LeaveRow) {
  const range = `${row.fromDate}${row.toDate ? ` → ${row.toDate}` : ''}`;
  const time = row.startTime ? ` · ${row.startTime}${row.endTime ? `–${row.endTime}` : ''}` : '';
  return `${range}${time}`;
}

export default function LeaveApprovalsPage() {
  const qc = useQueryClient();
  const [employeeQuery, setEmployeeQuery] = useState('');
  const [dateFilter, setDateFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('ALL');

  const queryParams = useMemo(
    () => ({
      ...(statusFilter !== 'ALL' ? { status: statusFilter } : {}),
      ...(employeeQuery.trim() ? { q: employeeQuery.trim() } : {}),
      ...(dateFilter ? { date: dateFilter } : {}),
    }),
    [statusFilter, employeeQuery, dateFilter],
  );

  const { data: items = [], isLoading } = useQuery<LeaveRow[]>({
    queryKey: ['org-leaves.admin', queryParams],
    queryFn: async () =>
      (await api.get('/employee-tracking/leaves', { params: queryParams })).data.items,
  });

  const approve = useMutation({
    mutationFn: (id: string) => api.patch(`/employee-tracking/leaves/${id}/approve`),
    onSuccess: () => {
      toast.success('Leave approved');
      qc.invalidateQueries({ queryKey: ['org-leaves.admin'] });
    },
    onError: () => toast.error('Could not approve leave'),
  });

  const reject = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason?: string }) =>
      api.patch(`/employee-tracking/leaves/${id}/reject`, { reason }),
    onSuccess: () => {
      toast.success('Leave rejected');
      qc.invalidateQueries({ queryKey: ['org-leaves.admin'] });
    },
    onError: () => toast.error('Could not reject leave'),
  });

  const pendingCount = useMemo(
    () => items.filter((row) => row.status === 'PENDING').length,
    [items],
  );

  return (
    <div className="la-approvals">
      <header className="la-approvals__head">
        <div>
          <h1>Leave requests</h1>
          <p>Review and approve organisation leave. Approved leave pauses employee GPS tracking.</p>
        </div>
        {!isLoading && pendingCount > 0 && (
          <span className="la-approvals__pending-pill">{pendingCount} pending</span>
        )}
      </header>

      <section className="la-approvals__toolbar">
        <Input
          className="la-approvals__search"
          label="Search employee"
          placeholder="Name, email, or user ID"
          value={employeeQuery}
          onChange={(e) => setEmployeeQuery(e.target.value)}
          leading={<Search size={16} />}
        />
        <label className="la-approvals__date">
          <span>Leave date</span>
          <input
            type="date"
            value={dateFilter}
            onChange={(e) => setDateFilter(e.target.value)}
          />
        </label>
      </section>

      <div className="la-approvals__chips" role="tablist" aria-label="Leave status">
        {STATUS_FILTERS.map((chip) => (
          <button
            key={chip.value}
            type="button"
            role="tab"
            aria-selected={statusFilter === chip.value}
            className={`la-approvals__chip${statusFilter === chip.value ? ' la-approvals__chip--active' : ''}`}
            onClick={() => setStatusFilter(chip.value)}
          >
            {chip.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <p className="la-approvals__empty">Loading…</p>
      ) : !items.length ? (
        <div className="la-approvals__empty la-approvals__empty--card">
          <p>No leave requests match your filters.</p>
          {(employeeQuery || dateFilter || statusFilter !== 'ALL') && (
            <button
              type="button"
              className="la-approvals__clear"
              onClick={() => {
                setEmployeeQuery('');
                setDateFilter('');
                setStatusFilter('ALL');
              }}
            >
              Clear filters
            </button>
          )}
        </div>
      ) : (
        <div className="la-approvals__list">
          {items.map((row) => (
            <article
              key={row.id}
              className={`la-approvals__card la-approvals__card--${row.status.toLowerCase()}`}
            >
              <div className="la-approvals__card-top">
                <div className="la-approvals__user">
                  <Avatar name={row.user.name} src={row.user.avatarUrl} size={40} />
                  <div>
                    <UserName name={row.user.name} role={row.user.role} />
                    <span>{leaveTypeLabel(row.leaveType)}</span>
                  </div>
                </div>
                <Badge tone={statusTone(row.status)} variant="soft">
                  {statusLabel(row.status)}
                </Badge>
              </div>
              <p className="la-approvals__dates">{formatDates(row)}</p>
              <p className="la-approvals__desc">{row.description}</p>
              {row.status === 'REJECTED' && row.rejectionReason && (
                <p className="la-approvals__meta">Reason: {row.rejectionReason}</p>
              )}
              {row.status !== 'PENDING' && row.approvedAt && (
                <p className="la-approvals__meta">
                  Reviewed {new Date(row.approvedAt).toLocaleString()}
                </p>
              )}
              {row.status === 'PENDING' && (
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
              )}
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
