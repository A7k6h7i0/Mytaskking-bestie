'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./reports.service');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

const ReportBody = Joi.string().min(1).max(1600).custom((value, helpers) => {
  if (service.wordCount(value) > 120) {
    return helpers.error('any.invalid');
  }
  return value;
}, '120-word report limit').messages({
  'any.invalid': 'Report must be 120 words or less',
});

const RecipientIds = Joi.array().items(Joi.string()).min(1).max(50).required();

router.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await service.listForUser(req.user));
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      body: ReportBody.required(),
      recipientIds: RecipientIds,
    }),
  }),
  asyncHandler(async (req, res) => {
    const report = await service.updateReport({
      id: req.params.id,
      user: req.user,
      body: req.body.body,
      recipientIds: req.body.recipientIds,
      io: req.app.get('io'),
    });
    audit.record({
      kind: 'task.report.updated',
      entity: 'task_report',
      entityId: report.id,
      payload: { taskId: report.taskId, recipientIds: req.body.recipientIds },
      req,
    });
    res.json(report);
  })
);

router.put(
  '/:id/response',
  validate({
    body: Joi.object({
      body: ReportBody.required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const report = await service.respond({
      id: req.params.id,
      user: req.user,
      body: req.body.body,
      io: req.app.get('io'),
    });
    audit.record({
      kind: 'task.report.responded',
      entity: 'task_report',
      entityId: report.id,
      payload: { taskId: report.taskId, userId: req.user.id },
      req,
    });
    res.json(report);
  })
);

module.exports = router;
