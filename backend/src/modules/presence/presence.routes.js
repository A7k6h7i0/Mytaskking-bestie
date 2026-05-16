'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');

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
    req.app.get('io')?.emit('presence.status', {
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
    const ids = req.query.userIds.split(',').filter(Boolean);
    const rows = await prisma.userPresence.findMany({ where: { userId: { in: ids } } });
    res.json({ items: rows });
  })
);

module.exports = router;
