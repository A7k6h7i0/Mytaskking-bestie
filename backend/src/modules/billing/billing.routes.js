'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const { authLimiter } = require('../../middleware/rateLimit');
const billing = require('../../services/billing.service');
const billingPlans = require('../../services/billingPlans.service');
const tenant = require('../../services/tenant');
const { Forbidden } = require('../../utils/errors');

const router = Router();

function requirePlatformSuperAdmin(req, _res, next) {
  if (!tenant.isPlatformSuperAdmin(req.user)) return next(Forbidden('Super admin only'));
  next();
}

router.get(
  '/plans',
  asyncHandler(async (_req, res) => {
    res.json({ items: await billing.listPlans() });
  })
);

router.post(
  '/trial',
  authLimiter,
  validate({ body: Joi.object({ tenantId: Joi.string().required() }) }),
  asyncHandler(async (req, res) => {
    const sub = await billing.requestTrial(req.body.tenantId);
    res.json({ ok: true, subscription: sub });
  })
);

router.post(
  '/razorpay/order',
  authLimiter,
  validate({
    body: Joi.object({
      tenantId: Joi.string().required(),
      planId: Joi.string(),
      planMonths: Joi.number().integer().min(1),
    }).or('planId', 'planMonths'),
  }),
  asyncHandler(async (req, res) => {
    res.json(
      await billing.createRazorpayOrder(req.body.tenantId, {
        planId: req.body.planId,
        planMonths: req.body.planMonths,
      })
    );
  })
);

router.post(
  '/razorpay/verify',
  authLimiter,
  validate({
    body: Joi.object({
      tenantId: Joi.string().required(),
      razorpayOrderId: Joi.string().required(),
      razorpayPaymentId: Joi.string().required(),
      razorpaySignature: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const sub = await billing.verifyRazorpayPayment(req.body);
    res.json({ ok: true, subscription: sub });
  })
);

router.get(
  '/status/:tenantId',
  authLimiter,
  asyncHandler(async (req, res) => {
    const sub = await billing.getSubscription(req.params.tenantId);
    res.json({ subscription: sub });
  })
);

router.use(requireAuth);
router.use(requirePlatformSuperAdmin);

router.get(
  '/admin/plans',
  asyncHandler(async (_req, res) => {
    res.json({ items: await billingPlans.listPlans({ activeOnly: false }) });
  })
);

router.post(
  '/admin/plans',
  validate({
    body: Joi.object({
      months: Joi.number().integer().min(1).required(),
      label: Joi.string().trim().min(2).max(120).required(),
      amountPaise: Joi.number().integer().min(100).required(),
      currency: Joi.string().default('INR'),
      isActive: Joi.boolean(),
      sortOrder: Joi.number().integer(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const plan = await billingPlans.createPlan(req.body);
    res.status(201).json(plan);
  })
);

router.patch(
  '/admin/plans/:id',
  validate({
    body: Joi.object({
      months: Joi.number().integer().min(1),
      label: Joi.string().trim().min(2).max(120),
      amountPaise: Joi.number().integer().min(100),
      currency: Joi.string(),
      isActive: Joi.boolean(),
      sortOrder: Joi.number().integer(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await billingPlans.updatePlan(req.params.id, req.body));
  })
);

router.delete(
  '/admin/plans/:id',
  asyncHandler(async (req, res) => {
    res.json(await billingPlans.deletePlan(req.params.id));
  })
);

module.exports = router;
