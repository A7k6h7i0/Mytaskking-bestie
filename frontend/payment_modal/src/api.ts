const API = import.meta.env.VITE_API_URL || 'https://mytaskking.com/api/v1';

export type Plan = {
  planMonths: number;
  label: string;
  amountPaise: number;
  amountInr: number;
  currency: string;
};

export async function fetchPlans(): Promise<Plan[]> {
  const res = await fetch(`${API}/billing/plans`);
  if (!res.ok) throw new Error('Could not load plans');
  const data = await res.json();
  return data.items || [];
}

export async function createOrder(tenantId: string, planMonths: number) {
  const res = await fetch(`${API}/billing/razorpay/order`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tenantId, planMonths }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.error || 'Order failed');
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
