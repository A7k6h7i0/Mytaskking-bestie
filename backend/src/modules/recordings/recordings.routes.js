'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');
const { NotFound } = require('../../utils/errors');

const router = Router();
router.use(requireAuth, requireAdmin);

// Unified recordings feed for the admin panel: every call and meeting room
// that has a stored recordingUrl, newest first. Recordings are produced
// client-side (mixed channel audio), uploaded as FileAssets, then attached
// to the call/meeting via their /recording endpoints.
router.get(
  '/',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(50),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { page, pageSize } = req.query;

    const [calls, meetings] = await Promise.all([
      prisma.call.findMany({
        where: { recordingUrl: { not: null } },
        include: {
          initiator: { select: { id: true, name: true } },
          participants: { include: { user: { select: { id: true, name: true } } } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.meetingRoom.findMany({
        where: { recordingUrl: { not: null } },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    const items = [
      ...calls.map((c) => ({
        id: c.id,
        source: 'CALL',
        title: `${c.kind === 'GROUP' ? 'Group call' : 'Call'} · ${c.initiator?.name || 'Unknown'}`,
        recordingUrl: c.recordingUrl,
        participants: (c.participants || []).map((p) => p.user?.name).filter(Boolean),
        startedAt: c.startedAt,
        endedAt: c.endedAt,
        createdAt: c.createdAt,
      })),
      ...meetings.map((m) => ({
        id: m.id,
        source: 'MEETING',
        title: m.name,
        recordingUrl: m.recordingUrl,
        participants: [],
        startedAt: m.scheduledAt,
        endedAt: m.endedAt,
        createdAt: m.createdAt,
      })),
    ].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    const total = items.length;
    const start = (page - 1) * pageSize;
    const pageItems = items.slice(start, start + pageSize);

    res.json({ items: pageItems, total, page, pageSize });
  })
);

router.delete(
  '/:source/:id',
  validate({
    params: Joi.object({
      source: Joi.string().valid('CALL', 'MEETING').required(),
      id: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { source, id } = req.params;
    const result = source === 'CALL'
      ? await prisma.call.updateMany({
          where: { id, recordingUrl: { not: null } },
          data: { recordingUrl: null },
        })
      : await prisma.meetingRoom.updateMany({
          where: { id, recordingUrl: { not: null } },
          data: { recordingUrl: null },
        });

    if (!result.count) throw NotFound('Recording not found');

    audit.record({
      kind: 'recording.deleted',
      entity: source === 'CALL' ? 'call' : 'meeting',
      entityId: id,
      payload: { source },
      req,
    });
    res.status(204).end();
  })
);

module.exports = router;
