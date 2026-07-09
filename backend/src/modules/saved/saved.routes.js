'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');

const router = Router();
router.use(requireAuth);

const SavedKind = Joi.string().valid('MESSAGE', 'FILE', 'TASK', 'CHANNEL', 'LEAD');

router.get(
  '/',
  validate({ query: Joi.object({ kind: SavedKind }) }),
  asyncHandler(async (req, res) => {
    const where = { userId: req.user.id, ...(req.query.kind ? { kind: req.query.kind } : {}) };
    const items = await prisma.savedItem.findMany({ where, orderBy: { createdAt: 'desc' } });
    const orgId = tenant.resolveTenantId(req);

    // hydrate the references so the UI doesn't need a second roundtrip
    const hydrators = {
      MESSAGE: (ids) => prisma.message.findMany({
        where: {
          id: { in: ids },
          ...(tenant.MULTI_TENANT ? { channel: { tenantId: orgId } } : {}),
        },
        include: { author: true, channel: true },
      }),
      FILE: (ids) => prisma.fileAsset.findMany({
        where: tenant.scopedWhere(req, { id: { in: ids } }),
      }),
      TASK: (ids) => prisma.task.findMany({
        where: tenant.tenantClause(req.user, { id: { in: ids } }),
      }),
      CHANNEL: (ids) => prisma.channel.findMany({
        where: tenant.tenantClause(req.user, { id: { in: ids } }),
      }),
      LEAD: (ids) => prisma.lead.findMany({
        where: tenant.tenantClause(req.user, { id: { in: ids } }),
      }),
    };

    const byKind = items.reduce((m, it) => ((m[it.kind] = m[it.kind] || []), m[it.kind].push(it.refId), m), {});
    const hydrated = {};
    await Promise.all(
      Object.entries(byKind).map(async ([k, ids]) => {
        const rows = await hydrators[k](ids);
        hydrated[k] = Object.fromEntries(rows.map((r) => [r.id, r]));
      })
    );

    res.json({
      items: items.map((it) => ({ ...it, target: hydrated[it.kind]?.[it.refId] || null })),
    });
  })
);

router.post(
  '/',
  validate({
    body: Joi.object({
      kind: SavedKind.required(),
      refId: Joi.string().required(),
      note: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const saved = await prisma.savedItem.upsert({
      where: { userId_kind_refId: { userId: req.user.id, kind: req.body.kind, refId: req.body.refId } },
      update: { note: req.body.note ?? null },
      create: { userId: req.user.id, kind: req.body.kind, refId: req.body.refId, note: req.body.note ?? null },
    });
    res.status(201).json(saved);
  })
);

router.delete(
  '/',
  validate({
    body: Joi.object({ kind: SavedKind.required(), refId: Joi.string().required() }),
  }),
  asyncHandler(async (req, res) => {
    await prisma.savedItem
      .delete({
        where: { userId_kind_refId: { userId: req.user.id, kind: req.body.kind, refId: req.body.refId } },
      })
      .catch(() => {});
    res.json({ ok: true });
  })
);

module.exports = router;
