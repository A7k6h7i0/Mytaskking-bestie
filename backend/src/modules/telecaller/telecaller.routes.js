'use strict';

const { Router } = require('express');
const Joi = require('joi');
const multer = require('multer');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireRole } = require('../../middleware/auth');
const service = require('./telecaller.service');
const dailyReport = require('../../services/telecallerDailyReport');

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

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
const telecallerAdmin = requireRole('SUPER_ADMIN', 'ADMIN');
const callOutcomes = [
  'REACHABLE',
  'NO_ANSWER',
  'NOT_RESPONDED',
  'BUSY',
  'SWITCHED_OFF',
  'FOLLOWUP_REQUIRED',
  'WRONG_NUMBER',
  'NOT_INTERESTED',
];

router.get(
  '/leads',
  telecallerOrAdmin,
  validate({
    query: Joi.object({
      q: Joi.string().allow(''),
      status: Joi.string().valid('NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'),
      ownerId: Joi.string(),
      assignedDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/),
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
      assignedFor: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/),
    }),
  }),
  asyncHandler(async (req, res) => res.status(201).json(await service.createLead(req.body, req.user)))
);

router.post(
  '/leads/bulk-distribute',
  telecallerAdmin,
  validate({
    body: Joi.object({
      telecallerIds: Joi.array().items(Joi.string()).min(1).required(),
      startDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).required(),
      endDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).required(),
      recordsPerTelecallerPerDay: Joi.number().integer().min(1).max(500).default(100),
      workingDays: Joi.array().items(Joi.number().integer().min(0).max(6)).default([1, 2, 3, 4, 5, 6]),
      source: Joi.string().allow('', null),
      records: Joi.array().items(Joi.object({
        name: Joi.string().min(1).max(120).required(),
        phone: Joi.string().min(6).max(32).required(),
        company: Joi.string().max(160).allow('', null),
        email: Joi.string().email().allow('', null),
        source: Joi.string().allow('', null),
        notes: Joi.string().allow('', null),
      })).min(1).max(50000).required(),
    }),
  }),
  asyncHandler(async (req, res) => res.status(201).json(await service.bulkDistributeLeads(req.body, req.user)))
);

router.post(
  '/leads/bulk-distribute-file',
  telecallerAdmin,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    const result = await service.bulkDistributeLeadsFromFile({
      file: req.file,
      input: req.body || {},
      creator: req.user,
    });
    res.status(201).json(result);
  })
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
  validate({
    body: Joi.object({
      mode: Joi.string().valid('EXOTEL', 'PHONE').default('EXOTEL'),
    }).default({}),
  }),
  asyncHandler(async (req, res) => {
    const payload = { leadId: req.params.id, agent: req.user };
    if (req.body.mode === 'PHONE') {
      return res.json(await service.logPhoneDial(payload));
    }
    return res.json(await service.clickToCall(payload));
  })
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

router.patch(
  '/calls/:id/outcome',
  telecallerOrAdmin,
  validate({
    body: Joi.object({
      outcome: Joi.string().valid(...callOutcomes).required(),
      notes: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.updateCallOutcome(req.params.id, req.body, req.user)))
);

router.post(
  '/calls/:id/recording',
  telecallerOrAdmin,
  validate({
    body: Joi.object({
      fileId: Joi.string().allow(null, ''),
      url: Joi.string().allow(null, ''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const updated = await service.attachCallRecording(req.params.id, req.body, req.user);
    res.json({ ok: true, recordingUrl: updated.recordingUrl });
  })
);

router.get(
  '/calls/daily-report.xlsx',
  telecallerAdmin,
  validate({
    query: Joi.object({
      date: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
      scope: Joi.string().valid('org', 'all').default('org'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const report = await dailyReport.buildDailyReportForUser({
      user: req.user,
      date: req.query.date,
      scope: req.query.scope,
    });
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${report.filename}"`);
    res.setHeader('X-Report-Call-Count', String(report.calls));
    res.send(report.buffer);
  })
);

router.get(
  '/followups/today',
  telecallerOrAdmin,
  asyncHandler(async (req, res) => res.json({ items: await service.followupsDueToday(req.user) }))
);

module.exports = router;
