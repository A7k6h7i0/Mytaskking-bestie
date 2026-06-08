'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { authLimiter } = require('../../middleware/rateLimit');
const { requireAuth } = require('../../middleware/auth');
const authService = require('./auth.service');
const audit = require('../../services/audit');

const router = Router();

router.get(
  '/login-requirements',
  authLimiter,
  validate({ query: Joi.object({ userId: Joi.string().trim().min(2).max(64).required() }) }),
  asyncHandler(async (req, res) => {
    const user = await require('../../database/prisma').user.findUnique({
      where: { userId: req.query.userId },
      select: { role: true, isClient: true },
    });
    res.json({ requiresSelfie: authService.requiresLoginSelfie(user) });
  })
);

router.post(
  '/login',
  authLimiter,
  validate({
    body: Joi.object({
      userId: Joi.string().trim().min(2).max(64).required(),
      password: Joi.string().min(6).max(200).required(),
      loginSource: Joi.string().valid('web', 'mobile').default('web'),
      selfieBase64: Joi.string().max(4500000).allow('', null),
      selfieMimeType: Joi.string().valid('image/jpeg', 'image/png').allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    try {
      const result = await authService.login({
        userId: req.body.userId,
        password: req.body.password,
        userAgent: req.headers['user-agent'],
        ip: req.ip,
        req,
        loginSource: req.body.loginSource,
        selfieBase64: req.body.selfieBase64,
        selfieMimeType: req.body.selfieMimeType,
      });
      audit.record({ actorId: result.user.id, kind: 'auth.login', entity: 'user', entityId: result.user.id, req });
      res.json(result);
    } catch (err) {
      audit.record({
        kind: 'auth.login_failed',
        entity: 'user',
        payload: { userId: req.body.userId, reason: err.code || 'unknown' },
        req,
      });
      throw err;
    }
  })
);

router.post(
  '/refresh',
  validate({
    body: Joi.object({ refreshToken: Joi.string().required() }),
  }),
  asyncHandler(async (req, res) => {
    const result = await authService.refresh({
      refreshToken: req.body.refreshToken,
      userAgent: req.headers['user-agent'],
      ip: req.ip,
      req,
    });
    audit.record({ actorId: result.user.id, kind: 'auth.refresh', entity: 'user', entityId: result.user.id, req });
    res.json(result);
  })
);

router.post(
  '/logout',
  validate({
    body: Joi.object({ refreshToken: Joi.string().allow('', null) }),
  }),
  asyncHandler(async (req, res) => {
    await authService.logout({ refreshToken: req.body.refreshToken });
    audit.record({ kind: 'auth.logout', entity: 'user', req });
    res.json({ ok: true });
  })
);

router.get(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    res.json({ user: authService.sanitize(req.user) });
  })
);

router.patch(
  '/me',
  requireAuth,
  validate({
    body: Joi.object({
      avatarUrl: Joi.string().uri().allow('', null).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const user = await authService.updateProfile({
      user: req.user,
      avatarUrl: req.body.avatarUrl,
    });
    audit.record({
      actorId: req.user.id,
      kind: 'profile.updated',
      entity: 'user',
      entityId: req.user.id,
      payload: { avatarUpdated: true },
      req,
    });
    res.json({ user });
  })
);

router.post(
  '/change-password',
  requireAuth,
  validate({
    body: Joi.object({
      currentPassword: Joi.string().min(6).max(200).required(),
      newPassword: Joi.string().min(8).max(200).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const result = await authService.changePassword({
      user: req.user,
      currentPassword: req.body.currentPassword,
      newPassword: req.body.newPassword,
    });
    audit.record({ actorId: req.user.id, kind: 'auth.password_changed', entity: 'user', entityId: req.user.id, req });
    res.json(result);
  })
);

module.exports = router;
