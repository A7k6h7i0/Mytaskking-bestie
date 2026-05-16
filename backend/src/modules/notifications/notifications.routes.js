'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./notifications.service');

const router = Router();
router.use(requireAuth);

router.get(
  '/',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(30),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.listMine({ user: req.user, ...req.query })))
);

router.post(
  '/read-all',
  asyncHandler(async (req, res) => {
    await service.markAllRead(req.user.id);
    res.json({ ok: true });
  })
);

router.post(
  '/:id/read',
  asyncHandler(async (req, res) => {
    await service.markRead(req.params.id, req.user.id);
    res.json({ ok: true });
  })
);

router.post(
  '/devices',
  validate({
    body: Joi.object({
      token: Joi.string().min(10).required(),
      platform: Joi.string().valid('ANDROID', 'IOS', 'WEB', 'WINDOWS', 'MACOS').required(),
    }),
  }),
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.registerDevice({ userId: req.user.id, ...req.body }))
  )
);

router.delete(
  '/devices/:token',
  asyncHandler(async (req, res) => {
    await service.removeDevice({ token: req.params.token });
    res.status(204).end();
  })
);

router.get(
  '/grouped',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(30),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.groupedListMine({ user: req.user, ...req.query })))
);

router.get(
  '/preferences',
  asyncHandler(async (req, res) => {
    const pref = await service.getPreferences(req.user.id);
    res.json(pref || { channels: {}, muteUntil: null });
  })
);

router.put(
  '/preferences',
  validate({
    body: Joi.object({
      channels: Joi.object().pattern(Joi.string(), Joi.string().valid('all', 'mentions', 'off')),
      muteUntil: Joi.date().iso().allow(null),
      quietHoursStart: Joi.number().integer().min(0).max(23).allow(null),
      quietHoursEnd: Joi.number().integer().min(0).max(23).allow(null),
      timezone: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.setPreferences(req.user.id, req.body)))
);

module.exports = router;
