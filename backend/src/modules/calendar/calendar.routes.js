'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const tenant = require('../../services/tenant');

const router = Router();
router.use(requireAuth);

const EventKind = Joi.string().valid('MEETING', 'TASK_DEADLINE', 'REMINDER', 'CALL', 'GENERAL');
const Recurrence = Joi.string().valid('NONE', 'DAILY', 'WEEKLY', 'MONTHLY');

const include = {
  owner: { select: { id: true, name: true, avatarUrl: true, isClient: true, role: true } },
  attendees: { include: { user: { select: { id: true, name: true, avatarUrl: true, isClient: true, role: true } } } },
};

router.get(
  '/',
  validate({
    query: Joi.object({
      from: Joi.date().iso().required(),
      to: Joi.date().iso().required(),
      view: Joi.string().valid('day', 'week', 'month').default('week'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { from, to, view } = req.query;
    if (to <= from) throw BadRequest('to must be after from');
    const items = await prisma.calendarEvent.findMany({
      where: {
        startsAt: { gte: from, lte: to },
        OR: [{ ownerId: req.user.id }, { attendees: { some: { userId: req.user.id } } }],
        ...(tenant.MULTI_TENANT
            ? { owner: { tenantId: tenant.userTenantId(req.user) } }
            : {}),
      },
      orderBy: { startsAt: 'asc' },
      include,
    });
    res.json({ view, items });
  })
);

router.post(
  '/',
  validate({
    body: Joi.object({
      title: Joi.string().min(1).max(240).required(),
      description: Joi.string().max(8000).allow('', null),
      kind: EventKind,
      startsAt: Joi.date().iso().required(),
      endsAt: Joi.date().iso().allow(null),
      allDay: Joi.boolean(),
      recurrence: Recurrence,
      location: Joi.string().allow('', null),
      channelId: Joi.string().allow(null, ''),
      taskId: Joi.string().allow(null, ''),
      callId: Joi.string().allow(null, ''),
      attendeeIds: Joi.array().items(Joi.string()).default([]),
    }),
  }),
  asyncHandler(async (req, res) => {
    const attendeeIds = req.body.attendeeIds.length
      ? await tenant.filterUserIdsInTenant(req, req.body.attendeeIds)
      : [];
    const event = await prisma.calendarEvent.create({
      data: {
        title: req.body.title,
        description: req.body.description || null,
        kind: req.body.kind || 'MEETING',
        startsAt: new Date(req.body.startsAt),
        endsAt: req.body.endsAt ? new Date(req.body.endsAt) : null,
        allDay: req.body.allDay || false,
        recurrence: req.body.recurrence || 'NONE',
        location: req.body.location || null,
        channelId: req.body.channelId || null,
        taskId: req.body.taskId || null,
        callId: req.body.callId || null,
        ownerId: req.user.id,
        attendees: attendeeIds.length
          ? { create: attendeeIds.map((uid) => ({ userId: uid })) }
          : undefined,
      },
      include,
    });
    req.app.get('io')?.emit('calendar.event.created', event);
    res.status(201).json(event);
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      title: Joi.string().min(1).max(240),
      description: Joi.string().allow('', null),
      startsAt: Joi.date().iso(),
      endsAt: Joi.date().iso().allow(null),
      allDay: Joi.boolean(),
      recurrence: Recurrence,
      location: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const existing = await prisma.calendarEvent.findUnique({
      where: { id: req.params.id },
      include: { owner: { select: { tenantId: true } } },
    });
    if (!existing) throw NotFound('Event not found');
    tenant.assertResourceInOrg(req, existing.owner.tenantId);
    if (existing.ownerId !== req.user.id && !['SUPER_ADMIN', 'ADMIN'].includes(req.user.role)) throw Forbidden();
    const data = { ...req.body };
    if (data.startsAt) data.startsAt = new Date(data.startsAt);
    if (data.endsAt) data.endsAt = new Date(data.endsAt);
    const event = await prisma.calendarEvent.update({ where: { id: req.params.id }, data, include });
    req.app.get('io')?.emit('calendar.event.updated', event);
    res.json(event);
  })
);

router.post(
  '/:id/rsvp',
  validate({ body: Joi.object({ status: Joi.string().valid('ACCEPTED', 'DECLINED', 'TENTATIVE').required() }) }),
  asyncHandler(async (req, res) => {
    const att = await prisma.calendarAttendee.upsert({
      where: { eventId_userId: { eventId: req.params.id, userId: req.user.id } },
      update: { status: req.body.status },
      create: { eventId: req.params.id, userId: req.user.id, status: req.body.status },
    });
    res.json(att);
  })
);

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const existing = await prisma.calendarEvent.findUnique({
      where: { id: req.params.id },
      include: { owner: { select: { tenantId: true } } },
    });
    if (!existing) return res.status(204).end();
    tenant.assertResourceInOrg(req, existing.owner.tenantId);
    if (existing.ownerId !== req.user.id && !['SUPER_ADMIN', 'ADMIN'].includes(req.user.role)) throw Forbidden();
    await prisma.calendarEvent.delete({ where: { id: req.params.id } });
    res.status(204).end();
  })
);

module.exports = router;
