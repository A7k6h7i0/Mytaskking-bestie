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
const config = require('../../config');

const router = Router();

const Mode = Joi.string().valid('VOICE', 'VIDEO', 'WEBINAR', 'LIVESTREAM');
const PUBLIC_BASE_URL = process.env.MEETING_PUBLIC_URL || config.cors.webOrigin?.[0] || 'http://localhost:5173';

function serializeRoom(room) {
  if (!room) return room;
  return {
    ...room,
    shareUrl: `${PUBLIC_BASE_URL.replace(/\/$/, '')}/meetings/join/${room.slug}`,
  };
}

router.get(
  '/public/:slug',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    res.json(serializeRoom(room));
  })
);

router.post(
  '/public/:slug/token',
  validate({
    body: Joi.object({
      guestName: Joi.string().trim().min(2).max(120).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const uid = `guest_${nanoid(12)}`;
    const token = agora.generateRtcToken({ channelName: room.channelName, uid });
    res.json({
      ...token,
      mode: room.mode,
      guestName: req.body.guestName.trim(),
      room: serializeRoom({ id: room.id, slug: room.slug, name: room.name, mode: room.mode }),
    });
  })
);

router.use(requireAuth);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const items = await prisma.meetingRoom.findMany({
      where: { OR: [{ hostId: req.user.id }, { tenantId: req.user.tenantId || 'default' }], endedAt: null },
      orderBy: { createdAt: 'desc' },
    });
    res.json({ items: items.map(serializeRoom) });
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
    res.status(201).json(serializeRoom(room));
  })
);

router.get(
  '/:slug',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    res.json(serializeRoom(room));
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
    res.json({ ...token, mode: room.mode, room: serializeRoom({ id: room.id, slug: room.slug, name: room.name, mode: room.mode }) });
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
