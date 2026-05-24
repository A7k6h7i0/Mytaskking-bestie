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
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const config = require('../../config');

const router = Router();

const Mode = Joi.string().valid('VOICE', 'VIDEO', 'WEBINAR', 'LIVESTREAM');
const PUBLIC_BASE_URL = process.env.MEETING_PUBLIC_URL || config.cors.webOrigin?.[0] || 'http://localhost:5173';

function serializeRoom(room) {
  if (!room) return room;
  const { participants, shareEvents, guestRequests, ...rest } = room;
  return {
    ...rest,
    shareUrl: `${PUBLIC_BASE_URL.replace(/\/$/, '')}/meetings/join/${rest.slug}`,
  };
}

function canManageRoom(room, user) {
  return room.hostId === user.id || ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
}

async function recordParticipant({ room, userId = null, displayName, joinedVia }) {
  if (userId) {
    const existing = await prisma.meetingRoomParticipant.findFirst({
      where: { roomId: room.id, userId },
    });
    if (existing) {
      return prisma.meetingRoomParticipant.update({
        where: { id: existing.id },
        data: { lastSeenAt: new Date(), displayName },
      });
    }
  }

  return prisma.meetingRoomParticipant.create({
    data: {
      roomId: room.id,
      userId,
      displayName,
      joinedVia,
    },
  });
}

function notifyMeetingJoin(io, room, participant) {
  io?.to(`user:${room.hostId}`).emit('meeting.participant.joined', {
    roomId: room.id,
    slug: room.slug,
    name: room.name,
    participant: {
      id: participant.id,
      displayName: participant.displayName,
      joinedVia: participant.joinedVia,
      joinedAt: participant.joinedAt,
      userId: participant.userId,
    },
  });
}

router.get(
  '/public/:slug',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    res.json(serializeRoom(room));
  })
);

router.get(
  '/public/:slug/lobby',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({
      where: { slug: req.params.slug },
      include: {
        participants: { orderBy: { joinedAt: 'desc' }, take: 20 },
        shareEvents: { orderBy: { copiedAt: 'desc' }, take: 20 },
        guestRequests: {
          where: { status: 'PENDING' },
          orderBy: { requestedAt: 'desc' },
          take: 20,
        },
      },
    });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    res.json({
      room: serializeRoom(room),
      participants: room.participants,
      shareHistory: room.shareEvents,
      pendingRequests: room.guestRequests.map((request) => ({
        id: request.id,
        guestName: request.guestName,
        requestedAt: request.requestedAt,
        status: request.status,
      })),
    });
  })
);

router.post(
  '/public/:slug/share',
  validate({
    body: Joi.object({
      copiedByName: Joi.string().trim().min(2).max(120).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const share = await prisma.meetingRoomShareEvent.create({
      data: {
        roomId: room.id,
        copiedByName: req.body.copiedByName.trim(),
      },
    });
    res.json(share);
  })
);

router.post(
  '/public/:slug/request-access',
  validate({
    body: Joi.object({
      guestName: Joi.string().trim().min(2).max(120).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const guestUid = `guest_${nanoid(12)}`;
    const request = await prisma.meetingRoomGuestRequest.create({
      data: {
        roomId: room.id,
        guestName: req.body.guestName.trim(),
        guestUid,
      },
    });
    req.app.get('io')?.emit('meeting.guest_request.created', {
      roomId: room.id,
      slug: room.slug,
      requestId: request.id,
      guestName: request.guestName,
    });
    res.status(201).json({
      requestId: request.id,
      status: request.status,
      guestName: request.guestName,
      requestedAt: request.requestedAt,
    });
  })
);

router.get(
  '/public/:slug/request-access/:requestId',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const request = await prisma.meetingRoomGuestRequest.findFirst({
      where: { id: req.params.requestId, roomId: room.id },
    });
    if (!request) throw NotFound('Guest request not found');
    res.json({
      requestId: request.id,
      status: request.status,
      guestName: request.guestName,
      requestedAt: request.requestedAt,
      reviewedAt: request.reviewedAt,
    });
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
    const guestName = req.body.guestName.trim();
    const guestUid = `guest_${nanoid(12)}`;
    const token = agora.generateRtcToken({ channelName: room.channelName, uid: guestUid });
    const participant = await recordParticipant({
      room,
      displayName: guestName,
      joinedVia: 'GUEST',
    }).catch(() => null);
    if (participant) notifyMeetingJoin(req.app.get('io'), room, participant);
    res.json({
      ...token,
      mode: room.mode,
      guestName,
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
      include: {
        _count: { select: { participants: true } },
        guestRequests: {
          where: { status: 'PENDING' },
          select: { id: true },
        },
      },
    });
    res.json({
      items: items.map((room) => ({
        ...serializeRoom(room),
        pendingGuestCount: room.guestRequests.length,
        participantCount: room._count.participants,
      })),
    });
  })
);

router.get(
  '/:slug/guest-requests',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (room.endedAt) throw BadRequest('Meeting has ended');
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const items = await prisma.meetingRoomGuestRequest.findMany({
      where: { roomId: room.id },
      orderBy: [{ status: 'asc' }, { requestedAt: 'desc' }],
      take: 50,
    });
    res.json({ items });
  })
);

router.post(
  '/:slug/guest-requests/:requestId/approve',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const request = await prisma.meetingRoomGuestRequest.update({
      where: { id: req.params.requestId },
      data: {
        status: 'APPROVED',
        approvedAt: new Date(),
        reviewedAt: new Date(),
        reviewedById: req.user.id,
        rejectedAt: null,
      },
    });
    req.app.get('io')?.emit('meeting.guest_request.approved', {
      roomId: room.id,
      requestId: request.id,
      guestName: request.guestName,
    });
    res.json(request);
  })
);

router.post(
  '/:slug/guest-requests/:requestId/reject',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const request = await prisma.meetingRoomGuestRequest.update({
      where: { id: req.params.requestId },
      data: {
        status: 'REJECTED',
        rejectedAt: new Date(),
        reviewedAt: new Date(),
        reviewedById: req.user.id,
        approvedAt: null,
      },
    });
    req.app.get('io')?.emit('meeting.guest_request.rejected', {
      roomId: room.id,
      requestId: request.id,
      guestName: request.guestName,
    });
    res.json(request);
  })
);

router.post(
  '/:slug/share',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const share = await prisma.meetingRoomShareEvent.create({
      data: {
        roomId: room.id,
        copiedById: req.user.id,
        copiedByName: req.user.name,
      },
    });
    res.json(share);
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
    if (room.endedAt) throw BadRequest('Meeting has ended');

    // Same Agora primitive as voice calls — video is just a different
    // publish track on the same channel. The token doesn't change shape.
    const token = agora.generateRtcToken({ channelName: room.channelName, uid: req.user.id });
    const participant = await recordParticipant({
      room,
      userId: req.user.id,
      displayName: req.user.name,
      joinedVia: 'INTERNAL',
    });
    if (req.user.id !== room.hostId) notifyMeetingJoin(req.app.get('io'), room, participant);
    res.json({ ...token, mode: room.mode, room: serializeRoom({ id: room.id, slug: room.slug, name: room.name, mode: room.mode }) });
  })
);

router.post(
  '/:slug/end',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) return res.status(204).end();
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const updated = await prisma.meetingRoom.update({ where: { id: room.id }, data: { endedAt: new Date() } });
    audit.record({ kind: 'meeting.ended', entity: 'meeting', entityId: room.id, req });
    await eventBus.publish('meeting.ended', { meetingId: room.id }, { tenantId: room.tenantId });
    res.json(updated);
  })
);

module.exports = router;
