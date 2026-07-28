import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { useState } from 'react';
import { api } from '@/services/api';
import { toast } from '@/components/Toast';
import './request-leave.css';

type LeaveRow = {
  id: string;
  leaveType: string;
  fromDate: string;
  toDate?: string | null;
  startTime?: string | null;
  endTime?: string | null;
  status: string;
  description: string;
};

const TYPES = [
  { value: 'FULL_DAY', label: 'Full day' },
  { value: 'HALF_DAY', label: 'Half day' },
  { value: 'PERMISSION', label: 'Permission' },
];

export default function RequestLeavePage() {
  const qc = useQueryClient();
  const [leaveType, setLeaveType] = useState('FULL_DAY');
  const [fromDate, setFromDate] = useState(dayjs().format('YYYY-MM-DD'));
  const [toDate, setToDate] = useState('');
  const [startTime, setStartTime] = useState('');
  const [endTime, setEndTime] = useState('');
  const [permissionHours, setPermissionHours] = useState('');
  const [description, setDescription] = useState('');

  const { data: mine = [] } = useQuery<LeaveRow[]>({
    queryKey: ['org-leaves.mine'],
    queryFn: async () => (await api.get('/employee-tracking/leaves', { params: { mine: 'true' } })).data.items,
  });

  const submit = useMutation({
    mutationFn: async () => {
      await api.post('/employee-tracking/leaves', {
        leaveType,
        fromDate,
        toDate: toDate || undefined,
        startTime: startTime || undefined,
        endTime: endTime || undefined,
        permissionHours: permissionHours ? Number(permissionHours) : undefined,
        description,
      });
    },
    onSuccess: () => {
      toast.success('Leave request submitted');
      setDescription('');
      setPermissionHours('');
      qc.invalidateQueries({ queryKey: ['org-leaves.mine'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Could not submit leave'),
  });

  return (
    <div className="rl">
      <header className="rl__head">
        <h1>Request a leave</h1>
        <p>Submit to your organisation admin. Approved leave pauses GPS tracking.</p>
      </header>

      <form
        className="rl__form"
        onSubmit={(e) => {
          e.preventDefault();
          if (description.trim().length < 5) {
            toast.error('Please add a description');
            return;
          }
          submit.mutate();
        }}
      >
        <label>
          Leave type
          <select value={leaveType} onChange={(e) => setLeaveType(e.target.value)}>
            {TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>
        </label>
        <label>
          From date
          <input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} required />
        </label>
        {(leaveType === 'FULL_DAY' || leaveType === 'PERMISSION') && (
          <label>
            {leaveType === 'FULL_DAY' ? 'To date (optional)' : 'End date (optional)'}
            <input type="date" value={toDate} min={fromDate} onChange={(e) => setToDate(e.target.value)} />
          </label>
        )}
        {(leaveType === 'HALF_DAY' || leaveType === 'PERMISSION') && (
          <>
            <label>
              Start time
              <input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} />
            </label>
            <label>
              End time
              <input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} />
            </label>
          </>
        )}
        {leaveType === 'PERMISSION' && (
          <label>
            Permission hours (optional)
            <input
              type="number"
              min={0.5}
              max={24}
              step={0.5}
              value={permissionHours}
              onChange={(e) => setPermissionHours(e.target.value)}
            />
          </label>
        )}
        <label className="rl__full">
          Description
          <textarea
            rows={4}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Reason for leave…"
            required
          />
        </label>
        <button type="submit" disabled={submit.isPending}>
          {submit.isPending ? 'Submitting…' : 'Submit request'}
        </button>
      </form>

      <section className="rl__list">
        <h2>Your requests</h2>
        {!mine.length ? (
          <p className="rl__empty">No leave requests yet.</p>
        ) : (
          mine.map((row) => (
            <article key={row.id} className="rl__card">
              <strong>{row.leaveType.replace('_', ' ')} · {row.status}</strong>
              <span>{row.fromDate}{row.toDate ? ` → ${row.toDate}` : ''}</span>
              <p>{row.description}</p>
            </article>
          ))
        )}
      </section>
    </div>
  );
}
