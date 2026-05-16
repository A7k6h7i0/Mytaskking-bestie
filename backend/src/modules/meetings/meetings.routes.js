'use strict';

const { Router } = require('express');
const Joi = require('joi');
const { nanoid } = require('nanoid');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const agora = require('../../services/agora');
const audit = require('../../services/audit');
const eventBus = require('../../services/eventBus');
const { NotFound, Forbidden } = require('../../utils/errors');

const router = Router();
router.use(requireAuth);

const Mode = Joi.string().valid('VOICE', 'VIDEO', 'WEBINAR', 'LIVESTREAM');

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const items = await prisma.meetingRoom.findMany({
      where: { OR: [{ hostId: req.user.id }, { tenantId: req.user.tenantId || 'default' }], endedAt: null },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ items });
  })
);

router.post(
  '/',
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(180).required(),
      mode: Mode.default('VIDEO'),
      scheduledAt: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const slug = nanoid(10);
    const room = await prisma.meetingRoom.create({
      data: {
        slug,
        name: req.body.name,
        mode: req.body.mode,
        channelName: `meet_${slug}`,
        hostId: req.user.id,
        scheduledAt: req.body.scheduledAt ? new Date(req.body.scheduledAt) : null,
        tenantId: req.user.tenantId || null,
      },
    });
    audit.record({ kind: 'meeting.created', entity: 'meeting', entityId: room.id, payload: { mode: room.mode }, req });
    await eventBus.publish('meeting.created', { meetingId: room.id, mode: room.mode }, { tenantId: room.tenantId });
    res.status(201).json(room);
  })
);

router.get(
  '/:slug',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    res.json(room);
  })
);

router.post(
  '/:slug/token',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');

    // Same Agora primitive as voice calls — video is just a different
    // publish track on the same channel. The token doesn't change shape.
    const token = agora.generateRtcToken({ channelName: room.channelName, uid: req.user.id });
    res.json({ ...token, mode: room.mode, room: { id: room.id, slug: room.slug, name: room.name } });
  })
);

router.post(
  '/:slug/end',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) return res.status(204).end();
    if (room.hostId !== req.user.id && !['SUPER_ADMIN', 'ADMIN'].includes(req.user.role)) throw Forbidden();
    const updated = await prisma.meetingRoom.update({ where: { id: room.id }, data: { endedAt: new Date() } });
    audit.record({ kind: 'meeting.ended', entity: 'meeting', entityId: room.id, req });
    await eventBus.publish('meeting.ended', { meetingId: room.id }, { tenantId: room.tenantId });
    res.json(updated);
  })
);

module.exports = router;
