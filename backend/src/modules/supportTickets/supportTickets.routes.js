'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./supportTickets.service');
const tenant = require('../../services/tenant');
const { Forbidden } = require('../../utils/errors');

const router = Router();

const issueTypeSchema = Joi.string().valid(
  'APP_CRASH',
  'LOGIN_ACCESS',
  'CALLS_MEETINGS',
  'CHAT_MESSAGES',
  'TASKS_REPORTS',
  'BILLING_SUBSCRIPTION',
  'OTHER'
);

const statusSchema = Joi.string().valid(
  'OPEN',
  'ASSIGNED',
  'IN_PROGRESS',
  'RESOLVED',
  'CLOSED'
);

router.get(
  '/meta',
  asyncHandler(async (_req, res) => {
    res.json({
      issueTypes: Object.entries(service.ISSUE_TYPE_LABELS).map(([value, label]) => ({
        value,
        label,
      })),
      statuses: Object.entries(service.STATUS_LABELS).map(([value, label]) => ({
        value,
        label,
      })),
    });
  })
);

router.post(
  '/',
  requireAuth,
  validate({
    body: Joi.object({
      issueType: issueTypeSchema.required(),
      description: Joi.string().trim().min(10).max(5000).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const ticket = await service.create(req, req.body);
    res.status(201).json(ticket);
  })
);

router.get(
  '/mine',
  requireAuth,
  asyncHandler(async (req, res) => {
    const items = await service.listMine(req);
    res.json({ items });
  })
);

router.get(
  '/check-status',
  requireAuth,
  validate({
    query: Joi.object({
      ticketNumber: Joi.string().trim().min(6).max(32).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const ticket = await service.checkStatus(req, req.query);
    res.json(ticket);
  })
);

router.get(
  '/admin',
  requireAuth,
  asyncHandler(async (req, res) => {
    if (!tenant.isPlatformSuperAdmin(req.user)) throw Forbidden('Super admin only');
    const items = await service.listAdmin(req);
    res.json({ items });
  })
);

router.get(
  '/assigned',
  requireAuth,
  asyncHandler(async (req, res) => {
    const items = await service.listAssigned(req);
    res.json({ items });
  })
);

router.get(
  '/assignees',
  requireAuth,
  validate({
    query: Joi.object({
      q: Joi.string().trim().max(100).allow(''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const items = await service.listAssignees(req, { q: req.query.q || '' });
    res.json({ items });
  })
);

router.patch(
  '/:id/assign',
  requireAuth,
  validate({
    body: Joi.object({
      assigneeId: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const ticket = await service.assign(req, req.params.id, req.body);
    res.json(ticket);
  })
);

router.patch(
  '/:id/status',
  requireAuth,
  validate({
    body: Joi.object({
      status: statusSchema.required(),
      resolutionNotes: Joi.string().trim().max(2000).allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const ticket = await service.updateStatus(req, req.params.id, req.body);
    res.json(ticket);
  })
);

module.exports = router;
