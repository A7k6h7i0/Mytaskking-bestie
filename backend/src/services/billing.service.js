'use strict';

const crypto = require('crypto');
const prisma = require('../database/prisma');
const { BadRequest, NotFound } = require('../utils/errors');

const PLANS = {
  1: { months: 1, amountPaise: Number(process.env.PLAN_1_MONTH_PAISE || 99900), label: '1 month' },
  6: { months: 6, amountPaise: Number(process.env.PLAN_6_MONTH_PAISE || 499900), label: '6 months' },
  12: { months: 12, amountPaise: Number(process.env.PLAN_12_MONTH_PAISE || 899900), label: '12 months' },
};

function listPlans() {
  return Object.entries(PLANS).map(([months, plan]) => ({
    planMonths: Number(months),
    label: plan.label,
    amountPaise: plan.amountPaise,
    amountInr: plan.amountPaise / 100,
    currency: 'INR',
  }));
}

function getPlan(planMonths) {
  const plan = PLANS[Number(planMonths)];
  if (!plan) throw BadRequest('Invalid subscription plan');
  return plan;
}

async function ensureSubscription(tenantId) {
  const existing = await prisma.tenantSubscription.findUnique({ where: { tenantId } });
  if (existing) return existing;
  return prisma.tenantSubscription.create({ data: { tenantId } });
}

async function requestTrial(tenantId) {
  await ensureSubscription(tenantId);
  return prisma.tenantSubscription.update({
    where: { tenantId },
    data: { status: 'TRIAL_REQUESTED' },
  });
}

async function createRazorpayOrder(tenantId, planMonths) {
  const tenant = await prisma.tenant.findUnique({
    where: { id: tenantId },
    include: { registration: true },
  });
  if (!tenant) throw NotFound('Organisation not found');
  const plan = getPlan(planMonths);
  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || !keySecret) throw BadRequest('Payment is not configured on server');

  const receipt = `org_${tenant.slug}_${plan.months}m_${Date.now()}`;
  const auth = Buffer.from(`${keyId}:${keySecret}`).toString('base64');
  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: plan.amountPaise,
      currency: 'INR',
      receipt,
      notes: { tenantId, planMonths: String(plan.months) },
    }),
  });
  const order = await res.json();
  if (!res.ok) throw BadRequest(order.error?.description || 'Could not create payment order');

  await ensureSubscription(tenantId);
  await prisma.tenantSubscription.update({
    where: { tenantId },
    data: {
      status: 'PAYMENT_PENDING',
      planMonths: plan.months,
      amountPaise: plan.amountPaise,
      currency: 'INR',
      paymentProvider: 'razorpay',
      razorpayOrderId: order.id,
    },
  });

  return {
    keyId,
    orderId: order.id,
    amountPaise: plan.amountPaise,
    amountInr: plan.amountPaise / 100,
    currency: 'INR',
    planMonths: plan.months,
    tenant: { id: tenant.id, name: tenant.name, slug: tenant.slug },
  };
}

async function verifyRazorpayPayment({
  tenantId,
  razorpayOrderId,
  razorpayPaymentId,
  razorpaySignature,
}) {
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keySecret) throw BadRequest('Payment is not configured on server');
  const body = `${razorpayOrderId}|${razorpayPaymentId}`;
  const expected = crypto.createHmac('sha256', keySecret).update(body).digest('hex');
  if (expected !== razorpaySignature) throw BadRequest('Invalid payment signature');

  const sub = await prisma.tenantSubscription.findUnique({ where: { tenantId } });
  if (!sub) throw NotFound('Subscription not found');
  if (sub.razorpayOrderId && sub.razorpayOrderId !== razorpayOrderId) {
    throw BadRequest('Order mismatch');
  }

  const paidUntil = new Date();
  paidUntil.setMonth(paidUntil.getMonth() + (sub.planMonths || 1));

  return prisma.tenantSubscription.update({
    where: { tenantId },
    data: {
      status: 'PAID',
      paidAt: new Date(),
      paidUntil,
      razorpayPaymentId,
      paymentReference: razorpayPaymentId,
    },
  });
}

async function getSubscription(tenantId) {
  return prisma.tenantSubscription.findUnique({ where: { tenantId } });
}

module.exports = {
  listPlans,
  getPlan,
  requestTrial,
  createRazorpayOrder,
  verifyRazorpayPayment,
  getSubscription,
};
