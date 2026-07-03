'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const { authLimiter } = require('../../middleware/rateLimit');
const service = require('./tenants.service');
const audit = require('../../services/audit');
const tenant = require('../../services/tenant');
const { Forbidden } = require('../../utils/errors');

function requirePlatformSuperAdmin(req, _res, next) {
  if (!tenant.isPlatformSuperAdmin(req.user)) return next(Forbidden('Platform super admin only'));
  next();
}

const router = Router();

// Public — used on login screen to validate organisation slug (no user list).
router.get(
  '/resolve',
  authLimiter,
  validate({ query: Joi.object({ slug: Joi.string().trim().min(2).max(48).required() }) }),
  asyncHandler(async (req, res) => {
    res.json(await service.resolvePublic(req.query.slug));
  })
);

router.use(requireAuth, requirePlatformSuperAdmin);

router.get(
  '/',
  asyncHandler(async (_req, res) => {
    res.json(await service.list());
  })
);

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    res.json(await service.getById(req.params.id));
  })
);

router.post(
  '/',
  validate({
    body: Joi.object({
      name: Joi.string().trim().min(2).max(120).required(),
      slug: Joi.string().trim().min(2).max(48).required(),
      adminName: Joi.string().trim().min(1).max(120).required(),
      adminUserId: Joi.string().trim().min(2).max(64).required(),
      adminPassword: Joi.string().min(8).max(200).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const result = await service.create({
      ...req.body,
      createdById: req.user.id,
    });
    audit.record({
      actorId: req.user.id,
      kind: 'tenant.created',
      entity: 'tenant',
      entityId: result.organisation.id,
      payload: { slug: result.organisation.slug, adminUserId: result.admin.userId },
      req,
    });
    res.status(201).json(result);
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      name: Joi.string().trim().min(2).max(120),
      status: Joi.string().valid('ACTIVE', 'SUSPENDED'),
      branding: Joi.object().unknown(true).allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const org = await service.update(req.params.id, req.body);
    audit.record({
      actorId: req.user.id,
      kind: 'tenant.updated',
      entity: 'tenant',
      entityId: org.id,
      payload: req.body,
      req,
    });
    res.json(org);
  })
);

module.exports = router;
