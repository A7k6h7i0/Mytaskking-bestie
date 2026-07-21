'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { authLimiter } = require('../../middleware/rateLimit');
const billing = require('../../services/billing.service');

const router = Router();

router.get(
  '/plans',
  asyncHandler(async (_req, res) => {
    res.json({ items: billing.listPlans() });
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
      planMonths: Joi.number().integer().valid(1, 6, 12).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await billing.createRazorpayOrder(req.body.tenantId, req.body.planMonths));
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

module.exports = router;
