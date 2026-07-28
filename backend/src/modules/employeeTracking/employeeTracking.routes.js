'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');
const service = require('./employeeTracking.service');
const {
  getSettings,
  scopedScope,
  KEYS,
  INTERVAL_OPTIONS,
} = require('./employeeTracking.settings');

const router = Router();
router.use(requireAuth);

const leaveTypeSchema = Joi.string().valid('FULL_DAY', 'HALF_DAY', 'PERMISSION');

router.get(
  '/settings',
  asyncHandler(async (req, res) => {
    res.json(await getSettings(req));
  })
);

router.patch(
  '/settings',
  requireAdmin,
  validate({
    body: Joi.object({
      gpsEnabled: Joi.boolean(),
      gpsIntervalSeconds: Joi.number()
        .valid(...INTERVAL_OPTIONS)
        .optional(),
    }).min(1),
  }),
  asyncHandler(async (req, res) => {
    const scope = scopedScope(req);
    for (const key of KEYS) {
      if (req.body[key] === undefined) continue;
      await prisma.workspaceSetting.upsert({
        where: { scope_key: { scope, key } },
        update: { value: req.body[key], updatedById: req.user.id },
        create: {
          scope,
          key,
          value: req.body[key],
          updatedById: req.user.id,
        },
      });
      audit.record({
        kind: 'settings.changed',
        entity: 'setting',
        entityId: `loginActivity.${key}`,
        payload: { value: req.body[key] },
        req,
      });
    }
    res.json(await getSettings(req));
  })
);

router.get(
  '/me/state',
  asyncHandler(async (req, res) => {
    res.json(await service.getTrackingState(req));
  })
);

router.post(
  '/gps',
  validate({
    body: Joi.object({
      latitude: Joi.number().required(),
      longitude: Joi.number().required(),
      accuracy: Joi.number().allow(null),
      logged_at: Joi.date().iso().optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await service.logGps(req, req.body));
  })
);

router.get(
  '/gps',
  asyncHandler(async (req, res) => {
    const items = await service.listGps(req, req.query);
    res.json({ items });
  })
);

router.get(
  '/live',
  asyncHandler(async (req, res) => {
    res.json(await service.liveLocations(req));
  })
);

router.post(
  '/leaves',
  validate({
    body: Joi.object({
      leaveType: leaveTypeSchema.required(),
      fromDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).required(),
      toDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).allow(null, ''),
      startTime: Joi.string().pattern(/^\d{2}:\d{2}$/).allow(null, ''),
      endTime: Joi.string().pattern(/^\d{2}:\d{2}$/).allow(null, ''),
      permissionHours: Joi.number().min(0.5).max(24).allow(null),
      description: Joi.string().trim().min(5).max(2000).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const leave = await service.createLeave(req, req.body);
    res.status(201).json(leave);
  })
);

router.get(
  '/leaves',
  asyncHandler(async (req, res) => {
    const items = await service.listLeaves(req, req.query);
    res.json({ items });
  })
);

router.patch(
  '/leaves/:id/approve',
  asyncHandler(async (req, res) => {
    res.json(await service.approveLeave(req, req.params.id));
  })
);

router.patch(
  '/leaves/:id/reject',
  validate({
    body: Joi.object({
      reason: Joi.string().trim().max(500).allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await service.rejectLeave(req, req.params.id, req.body));
  })
);

module.exports = router;
