'use strict';

const crypto = require('crypto');
const prisma = require('../database/prisma');
const logger = require('../utils/logger');
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

async function markSubscriptionPaid({ tenantId, razorpayOrderId, razorpayPaymentId }) {
  let sub = tenantId
    ? await prisma.tenantSubscription.findUnique({ where: { tenantId } })
    : null;

  if (!sub && razorpayOrderId) {
    sub = await prisma.tenantSubscription.findFirst({
      where: { razorpayOrderId },
    });
  }

  if (!sub) throw NotFound('Subscription not found for payment');

  const resolvedTenantId = sub.tenantId;
  if (razorpayOrderId && sub.razorpayOrderId && sub.razorpayOrderId !== razorpayOrderId) {
    throw BadRequest('Order mismatch');
  }

  if (
    sub.status === 'PAID' &&
    sub.razorpayPaymentId &&
    sub.razorpayPaymentId === razorpayPaymentId
  ) {
    return sub;
  }

  const paidUntil = new Date();
  paidUntil.setMonth(paidUntil.getMonth() + (sub.planMonths || 1));

  return prisma.tenantSubscription.update({
    where: { tenantId: resolvedTenantId },
    data: {
      status: 'PAID',
      paidAt: new Date(),
      paidUntil,
      razorpayOrderId: razorpayOrderId || sub.razorpayOrderId,
      razorpayPaymentId,
      paymentReference: razorpayPaymentId,
      paymentProvider: 'razorpay',
    },
  });
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

  return markSubscriptionPaid({ tenantId, razorpayOrderId, razorpayPaymentId });
}

function verifyWebhookSignature(rawBody, signature) {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!secret) throw BadRequest('Razorpay webhook is not configured on server');
  if (!signature) throw BadRequest('Missing Razorpay webhook signature');

  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(String(rawBody || ''), 'utf8');
  const expected = crypto.createHmac('sha256', secret).update(body).digest('hex');
  if (expected !== signature) throw BadRequest('Invalid webhook signature');
}

function parseWebhookPayload(rawBody) {
  const text = Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody || '');
  if (!text) throw BadRequest('Empty webhook body');
  try {
    return JSON.parse(text);
  } catch {
    throw BadRequest('Invalid webhook JSON');
  }
}

async function handleRazorpayWebhook(rawBody, signature) {
  verifyWebhookSignature(rawBody, signature);
  const event = parseWebhookPayload(rawBody);
  const eventType = event?.event;

  if (eventType === 'payment.captured') {
    const payment = event?.payload?.payment?.entity;
    const razorpayPaymentId = payment?.id;
    const razorpayOrderId = payment?.order_id;
    const tenantId = payment?.notes?.tenantId;

    if (!razorpayPaymentId || !razorpayOrderId) {
      logger.warn({ eventType }, 'razorpay.webhook.missing_payment_fields');
      return { ok: true, handled: false, reason: 'missing_payment_fields' };
    }

    try {
      const subscription = await markSubscriptionPaid({
        tenantId,
        razorpayOrderId,
        razorpayPaymentId,
      });
      logger.info(
        { eventType, tenantId: subscription.tenantId, razorpayPaymentId },
        'razorpay.webhook.payment_captured'
      );
      return { ok: true, handled: true, tenantId: subscription.tenantId };
    } catch (err) {
      if (err.status === 404) {
        logger.warn(
          { eventType, razorpayOrderId, tenantId, err: err.message },
          'razorpay.webhook.subscription_not_found'
        );
        return { ok: true, handled: false, reason: 'subscription_not_found' };
      }
      throw err;
    }
  }

  if (eventType === 'order.paid') {
    const order = event?.payload?.order?.entity;
    const payment = event?.payload?.payment?.entity;
    const razorpayOrderId = order?.id;
    const razorpayPaymentId = payment?.id;
    const tenantId = order?.notes?.tenantId || payment?.notes?.tenantId;

    if (!razorpayOrderId) {
      return { ok: true, handled: false, reason: 'missing_order_id' };
    }

    try {
      const subscription = await markSubscriptionPaid({
        tenantId,
        razorpayOrderId,
        razorpayPaymentId: razorpayPaymentId || `order_paid_${razorpayOrderId}`,
      });
      logger.info(
        { eventType, tenantId: subscription.tenantId, razorpayOrderId },
        'razorpay.webhook.order_paid'
      );
      return { ok: true, handled: true, tenantId: subscription.tenantId };
    } catch (err) {
      if (err.status === 404) {
        logger.warn({ eventType, razorpayOrderId }, 'razorpay.webhook.subscription_not_found');
        return { ok: true, handled: false, reason: 'subscription_not_found' };
      }
      throw err;
    }
  }

  if (eventType === 'payment.failed') {
    const payment = event?.payload?.payment?.entity;
    logger.info(
      {
        eventType,
        razorpayOrderId: payment?.order_id,
        tenantId: payment?.notes?.tenantId,
      },
      'razorpay.webhook.payment_failed'
    );
    return { ok: true, handled: false, reason: 'payment_failed_logged' };
  }

  logger.info({ eventType }, 'razorpay.webhook.ignored');
  return { ok: true, handled: false, reason: 'event_ignored' };
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
  handleRazorpayWebhook,
  getSubscription,
};
