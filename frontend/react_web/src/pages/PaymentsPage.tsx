import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { CreditCard, Plus, Trash2 } from 'lucide-react';
import clsx from 'clsx';
import { api } from '@/services/api';
import { toast } from '@/components/Toast';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Skeleton } from '@/components/ui/Skeleton';
import './people.css';

type BillingPlan = {
  id: string;
  planMonths: number;
  label: string;
  amountPaise: number;
  amountInr: number;
  currency: string;
  isActive: boolean;
  sortOrder: number;
};

const emptyForm = {
  label: '',
  months: '1',
  amountInr: '',
  sortOrder: '0',
  isActive: true,
};

export default function PaymentsPage() {
  const qc = useQueryClient();
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editForm, setEditForm] = useState(emptyForm);

  const { data, isLoading } = useQuery<{ items: BillingPlan[] }>({
    queryKey: ['billing.admin.plans'],
    queryFn: async () => (await api.get('/billing/admin/plans')).data,
  });

  const invalidate = () => qc.invalidateQueries({ queryKey: ['billing.admin.plans'] });

  const createMut = useMutation({
    mutationFn: async () =>
      (
        await api.post('/billing/admin/plans', {
          label: form.label.trim(),
          months: Number(form.months) || 1,
          amountPaise: Math.round((Number(form.amountInr) || 0) * 100),
          sortOrder: Number(form.sortOrder) || 0,
          isActive: form.isActive,
        })
      ).data,
    onSuccess: () => {
      invalidate();
      setCreating(false);
      setForm(emptyForm);
      toast.success('Plan created');
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not create plan'),
  });

  const updateMut = useMutation({
    mutationFn: async ({ id, body }: { id: string; body: Record<string, unknown> }) =>
      (await api.patch(`/billing/admin/plans/${id}`, body)).data,
    onSuccess: () => {
      invalidate();
      setEditingId(null);
      toast.success('Plan updated');
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not update plan'),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: string) => (await api.delete(`/billing/admin/plans/${id}`)).data,
    onSuccess: (result: { deleted?: boolean; deactivated?: boolean }) => {
      invalidate();
      toast.success(result.deactivated ? 'Plan deactivated (in use)' : 'Plan deleted');
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.error?.message || 'Could not remove plan'),
  });

  const plans = data?.items ?? [];

  function startEdit(plan: BillingPlan) {
    setEditingId(plan.id);
    setEditForm({
      label: plan.label,
      months: String(plan.planMonths),
      amountInr: String(plan.amountInr),
      sortOrder: String(plan.sortOrder),
      isActive: plan.isActive,
    });
  }

  return (
    <div className="pp">
      <header className="pp__head">
        <div>
          <h1 className="pp__title">Payments</h1>
          <p className="pp__sub">
            Manage subscription plans shown in checkout and org registration. Prices in INR.
          </p>
        </div>
        <Button onClick={() => setCreating((v) => !v)}>
          <Plus size={16} /> New plan
        </Button>
      </header>

      {creating && (
        <section className="pp__card m-fade-up" style={{ marginBottom: 20 }}>
          <h2 className="pp__card-title">Add plan</h2>
          <div className="pp__form-grid">
            <Input
              label="Label"
              value={form.label}
              onChange={(e) => setForm((f) => ({ ...f, label: e.target.value }))}
              placeholder="6 months"
            />
            <Input
              label="Duration (months)"
              type="number"
              value={form.months}
              onChange={(e) => setForm((f) => ({ ...f, months: e.target.value }))}
            />
            <Input
              label="Price (INR)"
              type="number"
              value={form.amountInr}
              onChange={(e) => setForm((f) => ({ ...f, amountInr: e.target.value }))}
              placeholder="4999"
            />
            <Input
              label="Sort order"
              type="number"
              value={form.sortOrder}
              onChange={(e) => setForm((f) => ({ ...f, sortOrder: e.target.value }))}
            />
          </div>
          <div className="pp__form-actions">
            <Button variant="ghost" onClick={() => setCreating(false)}>
              Cancel
            </Button>
            <Button onClick={() => createMut.mutate()} disabled={createMut.isPending}>
              Save plan
            </Button>
          </div>
        </section>
      )}

      <div className="pp__list">
        {isLoading &&
          Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} height={72} />)}
        {!isLoading &&
          plans.map((plan) => (
            <article key={plan.id} className="pp__row">
              <div className="pp__row-icon">
                <CreditCard size={18} />
              </div>
              <div className="pp__row-body">
                {editingId === plan.id ? (
                  <div className="pp__form-grid">
                    <Input
                      label="Label"
                      value={editForm.label}
                      onChange={(e) => setEditForm((f) => ({ ...f, label: e.target.value }))}
                    />
                    <Input
                      label="Months"
                      type="number"
                      value={editForm.months}
                      onChange={(e) => setEditForm((f) => ({ ...f, months: e.target.value }))}
                    />
                    <Input
                      label="Price (INR)"
                      type="number"
                      value={editForm.amountInr}
                      onChange={(e) => setEditForm((f) => ({ ...f, amountInr: e.target.value }))}
                    />
                    <Input
                      label="Sort"
                      type="number"
                      value={editForm.sortOrder}
                      onChange={(e) => setEditForm((f) => ({ ...f, sortOrder: e.target.value }))}
                    />
                    <label className="pp__check">
                      <input
                        type="checkbox"
                        checked={editForm.isActive}
                        onChange={(e) =>
                          setEditForm((f) => ({ ...f, isActive: e.target.checked }))
                        }
                      />
                      Active (visible in checkout)
                    </label>
                    <div className="pp__form-actions">
                      <Button variant="ghost" onClick={() => setEditingId(null)}>
                        Cancel
                      </Button>
                      <Button
                        onClick={() =>
                          updateMut.mutate({
                            id: plan.id,
                            body: {
                              label: editForm.label.trim(),
                              months: Number(editForm.months) || 1,
                              amountPaise: Math.round((Number(editForm.amountInr) || 0) * 100),
                              sortOrder: Number(editForm.sortOrder) || 0,
                              isActive: editForm.isActive,
                            },
                          })
                        }
                      >
                        Save
                      </Button>
                    </div>
                  </div>
                ) : (
                  <>
                    <div className="pp__row-title">
                      <strong>{plan.label}</strong>
                      <span
                        className={clsx(
                          'pp__badge',
                          plan.isActive ? 'pp__badge--ok' : 'pp__badge--muted',
                        )}
                      >
                        {plan.isActive ? 'Active' : 'Hidden'}
                      </span>
                    </div>
                    <div className="pp__row-meta">
                      {plan.planMonths} month{plan.planMonths === 1 ? '' : 's'} · ₹
                      {plan.amountInr.toLocaleString('en-IN')} · order {plan.sortOrder}
                    </div>
                  </>
                )}
              </div>
              {editingId !== plan.id && (
                <div className="pp__row-actions">
                  <Button variant="ghost" size="sm" onClick={() => startEdit(plan)}>
                    Edit
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      if (window.confirm(`Remove "${plan.label}"?`)) deleteMut.mutate(plan.id);
                    }}
                  >
                    <Trash2 size={14} />
                  </Button>
                </div>
              )}
            </article>
          ))}
        {!isLoading && plans.length === 0 && (
          <div className="pp__empty">No plans yet. Add one above.</div>
        )}
      </div>
    </div>
  );
}
