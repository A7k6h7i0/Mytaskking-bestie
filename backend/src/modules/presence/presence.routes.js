'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const cache = require('../../services/cache');
const tenant = require('../../services/tenant');

const router = Router();
router.use(requireAuth);

const Status = Joi.string().valid('ACTIVE', 'AWAY', 'BUSY', 'IN_MEETING', 'INVISIBLE');

router.put(
  '/me',
  validate({
    body: Joi.object({
      status: Status.required(),
      customStatus: Joi.string().max(64).allow('', null),
      expiresAt: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const row = await prisma.userPresence.upsert({
      where: { userId: req.user.id },
      update: req.body,
      create: { userId: req.user.id, ...req.body },
    });
    const io = req.app.get('io');
    const audience = ['ADMIN', 'SUPER_ADMIN'].includes(req.user.role)
      ? io?.to('role:ADMIN').to('role:SUPER_ADMIN')
      : io;
    audience?.emit('presence.status', {
      userId: req.user.id,
      status: row.status,
      customStatus: row.customStatus,
    });
    res.json(row);
  })
);

router.get(
  '/users',
  validate({
    query: Joi.object({ userIds: Joi.string().required() }),
  }),
  asyncHandler(async (req, res) => {
    const ids = await tenant.filterUserIdsInTenant(
      req,
      req.query.userIds.split(',').filter(Boolean),
    );
    const viewerCanSeeAdminPresence = ['ADMIN', 'SUPER_ADMIN'].includes(req.user.role);
    const rows = await prisma.userPresence.findMany({ where: { userId: { in: ids } } });
    const users = await prisma.user.findMany({
      where: tenant.scopedWhere(req, { id: { in: ids } }),
      select: { id: true, lastSeenAt: true, role: true },
    });
    const lastSeenByUser = new Map(users.map((user) => [
      user.id,
      !viewerCanSeeAdminPresence && ['ADMIN', 'SUPER_ADMIN'].includes(user.role)
        ? null
        : user.lastSeenAt,
    ]));
    const roleByUser = new Map(users.map((user) => [user.id, user.role]));
    const rowByUser = new Map(rows.map((row) => [row.userId, row]));
    const items = await Promise.all(
      ids.map(async (userId) => ({
        ...(rowByUser.get(userId) || { userId, status: 'ACTIVE', customStatus: null, expiresAt: null }),
        online: !viewerCanSeeAdminPresence && ['ADMIN', 'SUPER_ADMIN'].includes(roleByUser.get(userId))
          ? false
          : (await cache.get(`presence:online:${userId}`).catch(() => null)) === true,
        lastSeenAt: lastSeenByUser.get(userId) || null,
      }))
    );
    res.json({ items });
  })
);

module.exports = router;
