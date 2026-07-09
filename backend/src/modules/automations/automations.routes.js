'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const engine = require('../../services/automations');
const audit = require('../../services/audit');
const tenant = require('../../services/tenant');
const { Forbidden, NotFound } = require('../../utils/errors');

const router = Router();
router.use(requireAuth, requireAdmin);

const Trigger = Joi.string().valid(
  'TASK_OVERDUE', 'TASK_CREATED', 'TASK_STATUS_CHANGED',
  'RECURRING_SCHEDULE', 'LEAD_STATUS_CHANGED', 'CHANNEL_INACTIVE'
);
const Action = Joi.string().valid(
  'MOVE_TASK_STATUS', 'REASSIGN_TASK', 'NOTIFY_USER', 'NOTIFY_MANAGER', 'CREATE_TASK', 'POST_MESSAGE'
);

async function assertAutomationInOrg(req, id) {
  const automation = await prisma.automation.findUnique({ where: { id } });
  if (!automation) throw NotFound('Automation not found');
  if (tenant.MULTI_TENANT) {
    const creator = await prisma.user.findUnique({
      where: { id: automation.createdById },
      select: { tenantId: true },
    });
    tenant.assertResourceInOrg(req, creator?.tenantId);
  }
  return automation;
}

async function automationOrgWhere(req) {
  if (!tenant.MULTI_TENANT) return {};
  const users = await prisma.user.findMany({
    where: { tenantId: tenant.userTenantId(req.user) },
    select: { id: true },
  });
  return { createdById: { in: users.map((u) => u.id) } };
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const items = await prisma.automation.findMany({
      where: await automationOrgWhere(req),
      orderBy: { createdAt: 'desc' },
    });
    res.json({ items });
  })
);

router.post(
  '/',
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(120).required(),
      description: Joi.string().allow('', null),
      enabled: Joi.boolean().default(true),
      trigger: Trigger.required(),
      triggerData: Joi.object().unknown(true),
      action: Action.required(),
      actionData: Joi.object().unknown(true),
      scope: Joi.object().unknown(true),
    }),
  }),
  asyncHandler(async (req, res) => {
    const automation = await prisma.automation.create({
      data: {
        ...req.body,
        createdById: req.user.id,
        scope: {
          ...(req.body.scope || {}),
          tenantId: tenant.userTenantId(req.user),
        },
      },
    });
    await engine.registerSchedules();
    audit.record({ kind: 'automation.created', entity: 'automation', entityId: automation.id, req });
    res.status(201).json(automation);
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(120),
      description: Joi.string().allow('', null),
      enabled: Joi.boolean(),
      triggerData: Joi.object().unknown(true),
      actionData: Joi.object().unknown(true),
    }),
  }),
  asyncHandler(async (req, res) => {
    await assertAutomationInOrg(req, req.params.id);
    const automation = await prisma.automation.update({ where: { id: req.params.id }, data: req.body });
    await engine.registerSchedules();
    res.json(automation);
  })
);

router.post(
  '/:id/run',
  asyncHandler(async (req, res) => {
    const automation = await assertAutomationInOrg(req, req.params.id);
    await engine.runAction({ automation, context: {} });
    audit.record({ kind: 'automation.ran', entity: 'automation', entityId: req.params.id, req });
    res.json({ ok: true });
  })
);

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await assertAutomationInOrg(req, req.params.id);
    await prisma.automation.delete({ where: { id: req.params.id } }).catch(() => {});
    await engine.registerSchedules();
    res.status(204).end();
  })
);

module.exports = router;
