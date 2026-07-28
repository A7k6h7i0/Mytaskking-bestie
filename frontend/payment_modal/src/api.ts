const API = import.meta.env.VITE_API_URL || 'https://mytaskking.com/api/v1';

export type Plan = {
  id: string;
  planMonths: number;
  label: string;
  amountPaise: number;
  amountInr: number;
  currency: string;
  isActive?: boolean;
  sortOrder?: number;
};

export async function fetchPlans(): Promise<Plan[]> {
  const res = await fetch(`${API}/billing/plans`);
  if (!res.ok) throw new Error('Could not load plans');
  const data = await res.json();
  return data.items || [];
}

export async function fetchSubscriptionStatus(tenantId: string) {
  const res = await fetch(`${API}/billing/status/${tenantId}`);
  if (!res.ok) return null;
  const data = await res.json();
  return data.subscription as
    | {
        status?: string;
        paidUntil?: string | null;
        planMonths?: number;
        billingPlan?: { label?: string };
      }
    | null;
}

export function activePaidPlanMessage(
  sub: {
    status?: string;
    paidUntil?: string | null;
    planMonths?: number;
    billingPlan?: { label?: string };
  } | null,
) {
  if (!sub || sub.status !== 'PAID') return null;
  if (sub.paidUntil && new Date(sub.paidUntil) <= new Date()) return null;
  const plan = sub.billingPlan?.label || `${sub.planMonths || ''} month plan`.trim();
  const until = sub.paidUntil ? sub.paidUntil.slice(0, 10) : '';
  return until
    ? `You are already on the ${plan} plan (active until ${until}).`
    : `You are already on the ${plan} plan.`;
}

export async function createOrder(
  tenantId: string,
  options: { planId?: string; planMonths?: number },
) {
  const res = await fetch(`${API}/billing/razorpay/order`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tenantId, ...options }),
  });
  const data = await res.json();
  if (!res.ok) {
    const msg =
      data?.error?.message ||
      data?.message ||
      data?.error ||
      'Order failed';
    throw new Error(typeof msg === 'string' ? msg : 'Order failed');
  }
  return data;
}

export async function verifyPayment(payload: {
  tenantId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  razorpaySignature: string;
}) {
  const res = await fetch(`${API}/billing/razorpay/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.error || 'Verification failed');
  return data;
}

declare global {
  interface Window {
    Razorpay: new (options: Record<string, unknown>) => { open: () => void };
  }
}

export function openRazorpayCheckout(options: {
  keyId: string;
  orderId: string;
  amountPaise: number;
  orgName: string;
  onSuccess: (response: {
    razorpay_order_id: string;
    razorpay_payment_id: string;
    razorpay_signature: string;
  }) => void;
  onDismiss?: () => void;
}) {
  const rzp = new window.Razorpay({
    key: options.keyId,
    amount: options.amountPaise,
    currency: 'INR',
    name: 'MyTaskKing',
    description: `Subscription — ${options.orgName}`,
    order_id: options.orderId,
    handler: options.onSuccess,
    modal: {
      ondismiss: options.onDismiss,
    },
    theme: { color: '#2563eb' },
  });
  rzp.open();
}
