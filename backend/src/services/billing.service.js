'use strict';

const crypto = require('crypto');
const prisma = require('../database/prisma');
const { BadRequest, NotFound } = require('../utils/errors');
const billingPlans = require('./billingPlans.service');

async function listPlans() {
  return billingPlans.listPlans({ activeOnly: true });
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

async function createRazorpayOrder(tenantId, { planId, planMonths } = {}) {
  const tenant = await prisma.tenant.findUnique({
    where: { id: tenantId },
    include: { registration: true },
  });
  if (!tenant) throw NotFound('Organisation not found');
  const plan = await billingPlans.resolvePlan({ planId, planMonths });
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
      currency: plan.currency || 'INR',
      receipt,
      notes: { tenantId, planId: plan.id, planMonths: String(plan.months) },
    }),
  });
  const order = await res.json();
  if (!res.ok) throw BadRequest(order.error?.description || 'Could not create payment order');

  await ensureSubscription(tenantId);
  await prisma.tenantSubscription.update({
    where: { tenantId },
    data: {
      status: 'PAYMENT_PENDING',
      planId: plan.id,
      planMonths: plan.months,
      amountPaise: plan.amountPaise,
      currency: plan.currency || 'INR',
      paymentProvider: 'razorpay',
      razorpayOrderId: order.id,
    },
  });

  return {
    keyId,
    orderId: order.id,
    planId: plan.id,
    amountPaise: plan.amountPaise,
    amountInr: plan.amountPaise / 100,
    currency: plan.currency || 'INR',
    planMonths: plan.months,
    label: plan.label,
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
  return prisma.tenantSubscription.findUnique({
    where: { tenantId },
    include: { billingPlan: true },
  });
}

module.exports = {
  listPlans,
  requestTrial,
  createRazorpayOrder,
  verifyRazorpayPayment,
  getSubscription,
};
