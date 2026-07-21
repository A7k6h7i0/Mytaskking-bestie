import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  createOrder,
  fetchPlans,
  openRazorpayCheckout,
  verifyPayment,
  type Plan,
} from './api';

function resolveInitialPlan(plans: Plan[], param: string | null): string {
  if (!param || plans.length === 0) return plans[0]?.id ?? '';
  const byId = plans.find((p) => p.id === param);
  if (byId) return byId.id;
  const byMonths = plans.find((p) => p.planMonths === Number(param));
  return byMonths?.id ?? plans[0]?.id ?? '';
}

export default function CheckoutPage() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const tenantId = params.get('tenantId') || '';
  const planParam = params.get('plan');
  const [plans, setPlans] = useState<Plan[]>([]);
  const [selectedId, setSelectedId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchPlans()
      .then((items) => {
        setPlans(items);
        setSelectedId((current) => current || resolveInitialPlan(items, planParam));
      })
      .catch((e) => setError(e.message));
  }, [planParam]);

  const selectedPlan = useMemo(
    () => plans.find((p) => p.id === selectedId),
    [plans, selectedId],
  );

  async function payNow() {
    if (!tenantId) {
      setError('Missing tenantId in URL');
      return;
    }
    if (!selectedPlan) {
      setError('Choose a plan');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const order = await createOrder(tenantId, { planId: selectedPlan.id });
      const keyId = import.meta.env.VITE_RAZORPAY_KEY_ID || order.keyId;
      openRazorpayCheckout({
        keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        orgName: order.tenant?.name || 'Organisation',
        onSuccess: async (response) => {
          try {
            await verifyPayment({
              tenantId,
              razorpayOrderId: response.razorpay_order_id,
              razorpayPaymentId: response.razorpay_payment_id,
              razorpaySignature: response.razorpay_signature,
            });
            navigate('/success');
          } catch (e) {
            setError(e instanceof Error ? e.message : 'Payment verification failed');
            setLoading(false);
          }
        },
        onDismiss: () => setLoading(false),
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not start checkout');
      setLoading(false);
    }
  }

  return (
    <div className="page">
      <div className="card">
        <h1>MyTaskKing subscription</h1>
        <p className="muted">Choose a plan for your organisation. All prices in INR.</p>
        {!tenantId && <p className="error">Add ?tenantId=... to the URL from the app.</p>}
        <div className="plans">
          {plans.map((plan) => (
            <button
              key={plan.id}
              type="button"
              className={`plan ${selectedId === plan.id ? 'selected' : ''}`}
              onClick={() => setSelectedId(plan.id)}
            >
              <strong>{plan.label}</strong>
              <span>₹{plan.amountInr.toLocaleString('en-IN')}</span>
            </button>
          ))}
        </div>
        {selectedPlan && (
          <p className="summary">
            Selected: <strong>{selectedPlan.label}</strong> — ₹
            {selectedPlan.amountInr.toLocaleString('en-IN')}
          </p>
        )}
        {error && <p className="error">{error}</p>}
        <button type="button" className="primary" disabled={loading || !tenantId || !selectedPlan} onClick={payNow}>
          {loading ? 'Opening checkout…' : 'Pay now'}
        </button>
      </div>
    </div>
  );
}
