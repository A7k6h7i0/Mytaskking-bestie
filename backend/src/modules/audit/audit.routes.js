'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');

const router = Router();
router.use(requireAuth, requireAdmin);

router.get(
  '/',
  validate({
    query: Joi.object({
      q: Joi.string().allow(''),
      kind: Joi.string(),
      actorId: Joi.string(),
      entity: Joi.string(),
      from: Joi.date().iso(),
      to: Joi.date().iso(),
      cursor: Joi.string(),
      limit: Joi.number().integer().min(1).max(200).default(50),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { q, kind, actorId, entity, from, to, cursor, limit } = req.query;
    const where = {
      ...(tenant.MULTI_TENANT
        ? { actor: { tenantId: tenant.userTenantId(req.user) } }
        : {}),
      ...(kind ? { kind: { contains: kind } } : {}),
      ...(actorId ? { actorId } : {}),
      ...(entity ? { entity } : {}),
      ...(from || to
        ? { createdAt: { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } }
        : {}),
      ...(cursor ? { id: { lt: cursor } } : {}),
      ...(q
        ? {
            OR: [
              { kind: { contains: q, mode: 'insensitive' } },
              { entity: { contains: q, mode: 'insensitive' } },
              { entityId: { contains: q, mode: 'insensitive' } },
            ],
          }
        : {}),
    };
    const items = await prisma.activityLog.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
      include: {
        actor: { select: { id: true, name: true, role: true, avatarUrl: true, isClient: true } },
      },
    });
    res.json({ items, nextCursor: items.length === limit ? items[items.length - 1].id : null });
  })
);

router.get(
  '/kinds',
  asyncHandler(async (_req, res) => {
    const rows = await prisma.activityLog.groupBy({
      by: ['kind'],
      _count: { kind: true },
      orderBy: { _count: { kind: 'desc' } },
      take: 50,
    });
    res.json({ items: rows.map((r) => ({ kind: r.kind, count: r._count.kind })) });
  })
);

module.exports = router;
