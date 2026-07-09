'use strict';

const { Router } = require('express');
const Joi = require('joi');
const dayjs = require('dayjs');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');

const router = Router();
router.use(requireAuth, requireAdmin);

const rangeSchema = {
  query: Joi.object({
    from: Joi.date().iso().default(() => dayjs().subtract(30, 'day').toDate()),
    to: Joi.date().iso().default(() => new Date()),
    granularity: Joi.string().valid('day', 'week', 'month').default('day'),
  }),
};

function orgUserWhere(req, extra = {}) {
  return tenant.scopedWhere(req, extra);
}

function orgTaskWhere(user, extra = {}) {
  return tenant.tenantClause(user, extra);
}

function orgLeadWhere(user, extra = {}) {
  return tenant.tenantClause(user, extra);
}

function orgCallWhere(user, extra = {}) {
  return tenant.tenantClause(user, extra);
}

function orgAgentWhere(req, extra = {}) {
  if (!tenant.MULTI_TENANT) return extra;
  return { ...extra, agent: { tenantId: tenant.userTenantId(req.user) } };
}

function orgChannelMessageWhere(req, extra = {}) {
  if (!tenant.MULTI_TENANT) return extra;
  return {
    ...extra,
    channel: { tenantId: tenant.userTenantId(req.user) },
  };
}

router.get(
  '/productivity',
  validate(rangeSchema),
  asyncHandler(async (req, res) => {
    const { from, to } = req.query;
    const completed = await prisma.task.groupBy({
      by: ['createdById'],
      where: orgTaskWhere(req.user, { status: 'DONE', updatedAt: { gte: from, lte: to } }),
      _count: { _all: true },
    });
    const userIds = completed.map((c) => c.createdById);
    const users = await prisma.user.findMany({
      where: orgUserWhere(req, { id: { in: userIds } }),
      select: { id: true, name: true, avatarUrl: true, role: true, isClient: true },
    });
    const indexed = Object.fromEntries(users.map((u) => [u.id, u]));
    const items = completed
      .map((c) => ({ user: indexed[c.createdById], completed: c._count._all }))
      .filter((row) => row.user)
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
      where: orgAgentWhere(req, { createdAt: { gte: from, lte: to } }),
      _count: { _all: true },
      _sum: { durationSec: true },
    });
    const leadsWon = await prisma.lead.groupBy({
      by: ['ownerId'],
      where: orgLeadWhere(req.user, { status: 'WON', updatedAt: { gte: from, lte: to } }),
      _count: { _all: true },
    });
    const wonByOwner = Object.fromEntries(leadsWon.map((r) => [r.ownerId, r._count._all]));
    const ids = callsByAgent.map((c) => c.agentId);
    const agents = await prisma.user.findMany({
      where: orgUserWhere(req, { id: { in: ids } }),
      select: { id: true, name: true, avatarUrl: true },
    });
    const indexed = Object.fromEntries(agents.map((a) => [a.id, a]));
    const items = callsByAgent.map((c) => ({
      agent: indexed[c.agentId],
      calls: c._count._all,
      totalDurationSec: c._sum.durationSec || 0,
      leadsWon: wonByOwner[c.agentId] || 0,
    })).filter((row) => row.agent).sort((a, b) => b.calls - a.calls);
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
      where: orgTaskWhere(req.user, { createdAt: { gte: from, lte: to } }),
      _count: { _all: true },
    });
    const overdue = await prisma.task.count({
      where: orgTaskWhere(req.user, {
        dueAt: { lt: new Date() },
        status: { notIn: ['DONE', 'CANCELLED'] },
      }),
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
      prisma.message.count({
        where: orgChannelMessageWhere(req, { createdAt: { gte: from, lte: to } }),
      }),
      prisma.user.count({ where: orgUserWhere(req, { lastSeenAt: { gte: from } }) }),
      prisma.call.count({
        where: orgCallWhere(req.user, { createdAt: { gte: from, lte: to } }),
      }),
      prisma.telecallerCall.aggregate({
        where: orgAgentWhere(req, { createdAt: { gte: from, lte: to } }),
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
      where: orgUserWhere(req, { isClient: true, status: 'ACTIVE' }),
      select: { id: true, name: true, clientCompany: true, accessEndsAt: true },
    });
    const messageCounts = await prisma.message.groupBy({
      by: ['authorId'],
      where: orgChannelMessageWhere(req, {
        authorId: { in: clients.map((c) => c.id) },
        createdAt: { gte: from, lte: to },
      }),
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
      where: orgCallWhere(req.user, { createdAt: { gte: from, lte: to } }),
      _count: { _all: true },
    });
    res.json({
      from, to,
      byStatus: items.reduce((m, s) => ((m[s.status] = s._count._all), m), {}),
    });
  })
);

router.get(
  '/attendance',
  validate({
    query: Joi.object({
      from: Joi.date().iso().default(() => dayjs().subtract(30, 'day').toDate()),
      to: Joi.date().iso().default(() => new Date()),
      timezone: Joi.string().default('Asia/Kolkata'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const fromKey = dayjs(req.query.from).format('YYYY-MM-DD');
    const toKey = dayjs(req.query.to).format('YYYY-MM-DD');
    const todayKey = dayjs().format('YYYY-MM-DD');
    const items = await prisma.workdayLog.findMany({
      where: {
        localDate: { gte: fromKey, lte: toKey },
        ...(tenant.MULTI_TENANT
          ? { user: { tenantId: tenant.userTenantId(req.user) } }
          : {}),
      },
      orderBy: [{ localDate: 'desc' }],
      include: {
        user: {
          select: { id: true, name: true, userId: true, role: true, customTitle: true, avatarUrl: true, isClient: true },
        },
      },
    });

    const byUserMap = new Map();
    let checkedIn = 0;
    let checkedOut = 0;
    let lunchBreaks = 0;
    let missedCheckout = 0;

    for (const row of items) {
      const bucket = byUserMap.get(row.userId) || {
        user: row.user,
        checkedInDays: 0,
        checkedOutDays: 0,
        missedCheckoutDays: 0,
        lunchBreaks: 0,
        lastCheckInAt: null,
        lastCheckOutAt: null,
      };
      if (row.checkInAt) {
        checkedIn += 1;
        bucket.checkedInDays += 1;
        bucket.lastCheckInAt = bucket.lastCheckInAt || row.checkInAt;
      }
      if (row.checkOutAt) {
        checkedOut += 1;
        bucket.checkedOutDays += 1;
        bucket.lastCheckOutAt = bucket.lastCheckOutAt || row.checkOutAt;
      }
      if (row.lunchStartedAt) {
        lunchBreaks += 1;
        bucket.lunchBreaks += 1;
      }
      if (row.checkInAt && !row.checkOutAt && row.localDate < todayKey) {
        missedCheckout += 1;
        bucket.missedCheckoutDays += 1;
      }
      byUserMap.set(row.userId, bucket);
    }

    res.json({
      from: fromKey,
      to: toKey,
      totals: {
        checkedIn,
        checkedOut,
        lunchBreaks,
        missedCheckout,
      },
      byUser: Array.from(byUserMap.values()).sort((a, b) => b.missedCheckoutDays - a.missedCheckoutDays || b.checkedInDays - a.checkedInDays),
      recentMissedCheckout: items
        .filter((row) => row.checkInAt && !row.checkOutAt && row.localDate < todayKey)
        .slice(0, 20)
        .map((row) => ({
          id: row.id,
          localDate: row.localDate,
          checkInAt: row.checkInAt,
          user: row.user,
        })),
    });
  })
);

module.exports = router;
