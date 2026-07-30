'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin, requireInternal } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const audit = require('../../services/audit');
const service = require('./workActivity.service');

const router = Router();
router.use(requireAuth);

router.get(
  '/me/state',
  requireInternal,
  asyncHandler(async (req, res) => {
    res.json(await service.getStateForUser(req));
  })
);

router.post(
  '/desktop-session',
  requireInternal,
  validate({
    body: Joi.object({
      sessionId: Joi.string().allow('', null),
      latitude: Joi.number().min(-90).max(90).allow(null),
      longitude: Joi.number().min(-180).max(180).allow(null),
      address: Joi.string().max(500).allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const day = await service.registerDesktopSession(req, req.body);
    res.status(201).json(day);
  })
);

router.post(
  '/heartbeat',
  requireInternal,
  validate({
    body: Joi.object({
      idleSeconds: Joi.number().integer().min(0).required(),
      platform: Joi.string().valid('windows', 'linux').required(),
      deviceLabel: Joi.string().max(120).allow('', null),
      sessionId: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await service.processHeartbeat(req, req.body));
  })
);

router.post(
  '/clips',
  requireInternal,
  validate({
    body: Joi.object({
      fileId: Joi.string().allow('', null),
      clipUrl: Joi.string().uri().allow('', null),
      note: Joi.string().max(1000).allow('', null),
      status: Joi.string().max(48).default('WORKING'),
      platform: Joi.string().valid('windows', 'linux').required(),
      deviceLabel: Joi.string().max(120).allow('', null),
      durationSeconds: Joi.number().integer().min(0).max(30).default(5),
      captureStartedAt: Joi.date().iso().allow(null),
      captureEndedAt: Joi.date().iso().allow(null),
      promptShownAt: Joi.date().iso().allow(null),
      promptRespondedAt: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const clip = await service.createClip(req, req.body);
    audit.record({ kind: 'work_activity.clip_created', entity: 'work_activity', entityId: clip.id, req });
    req.app.get('io')?.to('role:ADMIN').to('role:SUPER_ADMIN').emit('work_activity.clip_created', clip);
    res.status(201).json(clip);
  })
);

router.get(
  '/summary',
  requireAdmin,
  validate({
    query: Joi.object({
      date: Joi.string().allow('', null),
      timezone: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await service.getSummary(req, {
      date: req.query.date || null,
      timezone: req.query.timezone || 'Asia/Kolkata',
    }));
  })
);

router.get(
  '/users/:userId/day',
  requireAdmin,
  validate({
    query: Joi.object({
      date: Joi.string().allow('', null),
      timezone: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await service.getUserDay(req, req.params.userId, {
      date: req.query.date || null,
      timezone: req.query.timezone || 'Asia/Kolkata',
    }));
  })
);

router.get(
  '/users/:userId/clips',
  requireAdmin,
  validate({
    query: Joi.object({
      date: Joi.string().allow('', null),
      from: Joi.date().iso().allow(null),
      to: Joi.date().iso().allow(null),
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(50),
    }),
  }),
  asyncHandler(async (req, res) => {
    await tenant.assertUserSameTenant(req, req.params.userId);
    const page = Number(req.query.page || 1);
    const pageSize = Number(req.query.pageSize || 50);
    let from = req.query.from ? new Date(req.query.from) : null;
    let to = req.query.to ? new Date(req.query.to) : null;
    if (req.query.date) {
      const { start, end } = (() => {
        const startDate = new Date(`${req.query.date}T00:00:00.000+05:30`);
        return { start: startDate, end: new Date(startDate.getTime() + 24 * 60 * 60 * 1000) };
      })();
      from = start;
      to = end;
    }
    const where = tenant.scopedWhere(req, {
      userId: req.params.userId,
      ...(from || to
        ? {
            captureStartedAt: {
              ...(from ? { gte: from } : {}),
              ...(to ? { lt: to } : {}),
            },
          }
        : {}),
    });
    const [total, items] = await prisma.$transaction([
      prisma.workActivityClip.count({ where }),
      prisma.workActivityClip.findMany({
        where,
        orderBy: { captureStartedAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
    ]);
    res.json({ total, page, pageSize, items });
  })
);

module.exports = router;
