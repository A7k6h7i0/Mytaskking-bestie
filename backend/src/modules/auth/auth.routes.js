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

router.post(
  '/login',
  authLimiter,
  validate({
    body: Joi.object({
      userId: Joi.string().trim().min(2).max(64).required(),
      password: Joi.string().min(6).max(200).required(),
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

module.exports = router;
