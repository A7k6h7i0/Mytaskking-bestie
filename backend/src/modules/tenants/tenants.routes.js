'use strict';

const { Router } = require('express');
const Joi = require('joi');
const multer = require('multer');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const { authLimiter } = require('../../middleware/rateLimit');
const service = require('./tenants.service');
const audit = require('../../services/audit');
const tenant = require('../../services/tenant');
const r2 = require('../../services/r2');
const cloudinary = require('../../services/cloudinary');
const { Forbidden, BadRequest } = require('../../utils/errors');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
});

function requirePlatformSuperAdmin(req, _res, next) {
  if (!tenant.isPlatformSuperAdmin(req.user)) return next(Forbidden('Platform super admin only'));
  next();
}

function requirePlatformStaff(req, _res, next) {
  if (!tenant.isPlatformStaff(req.user)) return next(Forbidden('Platform staff only'));
  next();
}

const govtIdSchema = Joi.string().valid('AADHAAR', 'PAN', 'VOTER_ID', 'DRIVING_LICENSE');

const registerBodySchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  slug: Joi.string().trim().min(2).max(48).required(),
  adminName: Joi.string().trim().min(1).max(120).required(),
  adminUserId: Joi.string().trim().min(2).max(64).required(),
  adminPassword: Joi.string().min(8).max(200).required(),
  adminEmail: Joi.string().trim().email().required(),
  adminPhone: Joi.string().trim().min(10).max(20).required(),
  govtId1Type: govtIdSchema.required(),
  govtId1Number: Joi.string().trim().min(4).max(32).required(),
  govtId1ImageUrl: Joi.string().uri().allow('', null),
  govtId2Type: govtIdSchema.required(),
  govtId2Number: Joi.string().trim().min(4).max(32).required(),
  govtId2ImageUrl: Joi.string().uri().allow('', null),
});

const basicRegisterBodySchema = Joi.object({
  name: Joi.string().trim().min(2).max(120).required(),
  slug: Joi.string().trim().min(2).max(48).required(),
  adminName: Joi.string().trim().min(1).max(120).required(),
  adminUserId: Joi.string().trim().min(2).max(64).required(),
  adminPassword: Joi.string().min(8).max(200).required(),
});

const router = Router();

router.get(
  '/resolve',
  authLimiter,
  validate({ query: Joi.object({ slug: Joi.string().trim().min(2).max(48).required() }) }),
  asyncHandler(async (req, res) => {
    res.json(await service.resolvePublic(req.query.slug));
  })
);

router.post(
  '/register',
  authLimiter,
  validate({ body: registerBodySchema }),
  asyncHandler(async (req, res) => {
    const result = await service.register(req.body);
    res.status(201).json({
      message:
        'Registration submitted. Our sales team will review your organisation before you can sign in.',
      organisation: result.organisation,
      adminUserId: result.admin.userId,
      tenantId: result.organisation.id,
    });
  })
);

router.post(
  '/register/upload',
  authLimiter,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) throw BadRequest('No file uploaded');
    if (!req.file.mimetype.startsWith('image/')) {
      throw BadRequest('Only image uploads are allowed');
    }
    if (cloudinary.isConfigured()) {
      const result = await cloudinary.uploadBuffer(req.file.buffer, {
        folder: 'bestie/org-registration',
      });
      return res.status(201).json({ url: result.secure_url });
    }
    if (r2.isConfigured()) {
      const safeName = (req.file.originalname || 'id.jpg').replace(/[^\w.-]/g, '_');
      const put = await r2.putBuffer({
        buffer: req.file.buffer,
        key: `org-registration/${Date.now()}-${safeName}`,
        contentType: req.file.mimetype,
      });
      return res.status(201).json({ url: put.url });
    }
    throw BadRequest('File storage is not configured');
  })
);

router.use(requireAuth, requirePlatformStaff);

router.get(
  '/registrations',
  asyncHandler(async (_req, res) => {
    res.json(await service.listRegistrations());
  })
);

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
  requirePlatformSuperAdmin,
  validate({ body: basicRegisterBodySchema }),
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
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const org = await service.approveRegistration(req.params.id, req.user.id);
    audit.record({
      actorId: req.user.id,
      kind: 'tenant.registration_approved',
      entity: 'tenant',
      entityId: org.id,
      req,
    });
    res.json(org);
  })
);

router.patch(
  '/:id/reject',
  validate({
    body: Joi.object({ reason: Joi.string().trim().max(500).allow('', null) }),
  }),
  asyncHandler(async (req, res) => {
    const org = await service.rejectRegistration(req.params.id, req.user.id, req.body.reason);
    audit.record({
      actorId: req.user.id,
      kind: 'tenant.registration_rejected',
      entity: 'tenant',
      entityId: org.id,
      payload: { reason: req.body.reason },
      req,
    });
    res.json(org);
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      name: Joi.string().trim().min(2).max(120),
      status: Joi.string().valid('ACTIVE', 'SUSPENDED', 'PENDING'),
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

router.patch(
  '/:id/subscription',
  requirePlatformSuperAdmin,
  validate({
    body: Joi.object({
      status: Joi.string().valid(
        'NONE',
        'TRIAL_REQUESTED',
        'TRIAL_ACTIVE',
        'PAYMENT_PENDING',
        'PAID',
        'EXPIRED'
      ),
      planId: Joi.string(),
      planMonths: Joi.number().integer().min(1),
      trialEndsAt: Joi.date().iso().allow(null),
      paidUntil: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const org = await service.updateSubscription(req.params.id, req.body);
    res.json(org);
  })
);

router.delete(
  '/:id',
  requirePlatformSuperAdmin,
  asyncHandler(async (req, res) => {
    await service.remove(req.params.id);
    audit.record({
      actorId: req.user.id,
      kind: 'tenant.deleted',
      entity: 'tenant',
      entityId: req.params.id,
      req,
    });
    res.json({ ok: true });
  })
);

module.exports = router;
