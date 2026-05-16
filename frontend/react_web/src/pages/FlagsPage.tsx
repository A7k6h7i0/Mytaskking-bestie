import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Flag, Plus } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Skeleton } from '@/components/ui/Skeleton';
import { toast } from '@/components/Toast';
import './flags.css';

type FlagRow = {
  key: string;
  description: string | null;
  enabled: boolean;
  rollout: 'GLOBAL' | 'ROLE' | 'USER' | 'TENANT' | 'PERCENT';
  payload: unknown;
  percent: number | null;
  roles: string[];
  tenantIds: string[];
};

export default function FlagsPage() {
  const qc = useQueryClient();
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ key: '', description: '', enabled: false, rollout: 'GLOBAL' as FlagRow['rollout'], percent: 0 });

  const { data, isLoading } = useQuery<{ items: FlagRow[] }>({
    queryKey: ['flags.all'],
    queryFn: async () => (await api.get('/flags')).data,
  });

  const upsert = useMutation({
    mutationFn: async ({ key, ...body }: Partial<FlagRow> & { key: string }) =>
      (await api.put(`/flags/${key}`, body)).data,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['flags.all'] });
      qc.invalidateQueries({ queryKey: ['flags.mine'] });
      toast.success('Flag updated');
    },
  });

  return (
    <div className="fl">
      <header className="fl__head">
        <div>
          <h1>Feature flags</h1>
          <p>Gradual rollout · role gating · percentage rollouts. Resolution refreshes every 30 s for live users.</p>
        </div>
        <Button onClick={() => setCreating((v) => !v)}><Plus size={16}/> New flag</Button>
      </header>

      {creating && (
        <div className="fl__create">
          <Input label="Key" placeholder="ai.task_summary" value={form.key} onChange={(e) => setForm({ ...form, key: e.target.value })} />
          <Input label="Description" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
          <label className="fl__select">
            <span>Rollout</span>
            <select value={form.rollout} onChange={(e) => setForm({ ...form, rollout: e.target.value as FlagRow['rollout'] })}>
              <option value="GLOBAL">Global</option>
              <option value="ROLE">Role</option>
              <option value="USER">User</option>
              <option value="TENANT">Tenant</option>
              <option value="PERCENT">Percent</option>
            </select>
          </label>
          {form.rollout === 'PERCENT' && (
            <Input label="% of users" type="number" value={String(form.percent)} onChange={(e) => setForm({ ...form, percent: Number(e.target.value) || 0 })} />
          )}
          <div className="fl__create-actions">
            <Button variant="ghost" onClick={() => setCreating(false)}>Cancel</Button>
            <Button onClick={() => { upsert.mutate({ key: form.key, ...form }); setCreating(false); }}>Save</Button>
          </div>
        </div>
      )}

      <div className="fl__list">
        {isLoading && Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} height={64} />)}
        {data?.items.map((f) => (
          <article key={f.key} className="fl__row">
            <div className="fl__icon"><Flag size={16} /></div>
            <div className="fl__body">
              <div className="fl__title">
                <code>{f.key}</code>
                <span className={`fl__rollout fl__rollout--${f.rollout.toLowerCase()}`}>{f.rollout}{f.rollout === 'PERCENT' ? ` · ${f.percent}%` : ''}</span>
              </div>
              {f.description && <div className="fl__desc">{f.description}</div>}
            </div>
            <button
              className={clsx('fl__toggle', f.enabled && 'is-on')}
              onClick={() => upsert.mutate({ key: f.key, enabled: !f.enabled })}
              title={f.enabled ? 'Disable' : 'Enable'}
            >
              <span className="fl__toggle-knob" />
            </button>
          </article>
        ))}
        {!isLoading && (data?.items.length ?? 0) === 0 && <div className="fl__empty">No flags yet. Define one above.</div>}
      </div>
    </div>
  );
}
