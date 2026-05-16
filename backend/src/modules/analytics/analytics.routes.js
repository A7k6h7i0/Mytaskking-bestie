'use strict';

const { Router } = require('express');
const Joi = require('joi');
const dayjs = require('dayjs');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');

const router = Router();
router.use(requireAuth, requireAdmin);

const rangeSchema = {
  query: Joi.object({
    from: Joi.date().iso().default(() => dayjs().subtract(30, 'day').toDate()),
    to: Joi.date().iso().default(() => new Date()),
    granularity: Joi.string().valid('day', 'week', 'month').default('day'),
  }),
};

router.get(
  '/productivity',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const completed = await prisma.task.groupBy({
      by: ['createdById'],
      where: { status: 'DONE', updatedAt: { gte: from, lte: to } },
      _count: { _all: true },
    });
    const userIds = completed.map((c) => c.createdById);
    const users = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, name: true, avatarUrl: true, role: true, isClient: true },
    });
    const indexed = Object.fromEntries(users.map((u) => [u.id, u]));
    const items = completed
      .map((c) => ({ user: indexed[c.createdById], completed: c._count._all }))
      .sort((a, b) => b.completed - a.completed);
    res.json({ from, to, items });
  })
);

router.get(
  '/telecaller',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const callsByAgent = await prisma.telecallerCall.groupBy({
      by: ['agentId'],
      where: { createdAt: { gte: from, lte: to } },
      _count: { _all: true },
      _sum: { durationSec: true },
    });
    const leadsWon = await prisma.lead.groupBy({
      by: ['ownerId'],
      where: { status: 'WON', updatedAt: { gte: from, lte: to } },
      _count: { _all: true },
    });
    const wonByOwner = Object.fromEntries(leadsWon.map((r) => [r.ownerId, r._count._all]));
    const ids = callsByAgent.map((c) => c.agentId);
    const agents = await prisma.user.findMany({
      where: { id: { in: ids } },
      select: { id: true, name: true, avatarUrl: true },
    });
    const indexed = Object.fromEntries(agents.map((a) => [a.id, a]));
    const items = callsByAgent.map((c) => ({
      agent: indexed[c.agentId],
      calls: c._count._all,
      totalDurationSec: c._sum.durationSec || 0,
      leadsWon: wonByOwner[c.agentId] || 0,
    })).sort((a, b) => b.calls - a.calls);
    res.json({ from, to, items });
  })
);

router.get(
  '/tasks',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const byStatus = await prisma.task.groupBy({
      by: ['status'],
      where: { createdAt: { gte: from, lte: to } },
      _count: { _all: true },
    });
    const overdue = await prisma.task.count({
      where: { dueAt: { lt: new Date() }, status: { notIn: ['DONE', 'CANCELLED'] } },
    });
    res.json({
      from, to,
      byStatus: byStatus.reduce((m, s) => ((m[s.status] = s._count._all), m), {}),
      overdue,
    });
  })
);

router.get(
  '/workspace',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const [messages, activeUsers, calls, callDurationSum] = await prisma.$transaction([
      prisma.message.count({ where: { createdAt: { gte: from, lte: to } } }),
      prisma.user.count({ where: { lastSeenAt: { gte: from } } }),
      prisma.call.count({ where: { createdAt: { gte: from, lte: to } } }),
      prisma.telecallerCall.aggregate({
        where: { createdAt: { gte: from, lte: to } },
        _sum: { durationSec: true },
      }),
    ]);
    res.json({ from, to, messages, activeUsers, calls, telecallerSeconds: callDurationSum._sum.durationSec || 0 });
  })
);

router.get(
  '/client-engagement',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const clients = await prisma.user.findMany({
      where: { isClient: true, status: 'ACTIVE' },
      select: { id: true, name: true, clientCompany: true, accessEndsAt: true },
    });
    const messageCounts = await prisma.message.groupBy({
      by: ['authorId'],
      where: { authorId: { in: clients.map((c) => c.id) }, createdAt: { gte: from, lte: to } },
      _count: { _all: true },
    });
    const indexed = Object.fromEntries(messageCounts.map((r) => [r.authorId, r._count._all]));
    const items = clients
      .map((c) => ({ client: c, messages: indexed[c.id] || 0 }))
      .sort((a, b) => b.messages - a.messages);
    res.json({ from, to, items });
  })
);

router.get(
  '/calls',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const items = await prisma.call.groupBy({
      by: ['status'],
      where: { createdAt: { gte: from, lte: to } },
      _count: { _all: true },
    });
    res.json({
      from, to,
      byStatus: items.reduce((m, s) => ((m[s.status] = s._count._all), m), {}),
    });
  })
);

module.exports = router;
