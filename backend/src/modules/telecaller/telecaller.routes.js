'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireRole } = require('../../middleware/auth');
const service = require('./telecaller.service');

const router = Router();

// Webhook is unauthenticated (Exotel will POST here)
router.post(
  '/webhook',
  asyncHandler(async (req, res) => {
    await service.handleWebhook(req.body || {});
    res.status(200).send('OK');
  })
);

router.use(requireAuth);

const telecallerOrAdmin = requireRole('SUPER_ADMIN', 'ADMIN', 'TELECALLER');

router.get(
  '/leads',
  telecallerOrAdmin,
  validate({
    query: Joi.object({
      q: Joi.string().allow(''),
      status: Joi.string().valid('NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'),
      ownerId: Joi.string(),
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(25),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.listLeads({ user: req.user, ...req.query })))
);

router.get(
  '/leads/:id',
  telecallerOrAdmin,
  asyncHandler(async (req, res) => res.json(await service.getLead(req.params.id, req.user)))
);

router.post(
  '/leads',
  telecallerOrAdmin,
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(120).required(),
      phone: Joi.string().min(6).max(32).required(),
      company: Joi.string().max(160).allow('', null),
      email: Joi.string().email().allow('', null),
      status: Joi.string().valid('NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'),
      ownerId: Joi.string(),
      source: Joi.string().allow('', null),
      notes: Joi.string().allow('', null),
      tags: Joi.array().items(Joi.string()),
      nextFollowAt: Joi.date().iso(),
    }),
  }),
  asyncHandler(async (req, res) => res.status(201).json(await service.createLead(req.body, req.user)))
);

router.patch(
  '/leads/:id',
  telecallerOrAdmin,
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(120),
      phone: Joi.string().min(6).max(32),
      company: Joi.string().max(160).allow('', null),
      email: Joi.string().email().allow('', null),
      status: Joi.string().valid('NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'),
      ownerId: Joi.string(),
      notes: Joi.string().allow('', null),
      tags: Joi.array().items(Joi.string()),
      nextFollowAt: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.updateLead(req.params.id, req.body, req.user)))
);

router.post(
  '/leads/:id/call',
  telecallerOrAdmin,
  asyncHandler(async (req, res) => res.json(await service.clickToCall({ leadId: req.params.id, agent: req.user })))
);

router.get(
  '/calls',
  telecallerOrAdmin,
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(50),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.callHistory({ user: req.user, ...req.query })))
);

router.get(
  '/followups/today',
  telecallerOrAdmin,
  asyncHandler(async (req, res) => res.json({ items: await service.followupsDueToday(req.user) }))
);

module.exports = router;
