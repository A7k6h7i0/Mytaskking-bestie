'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');
const tenant = require('../../services/tenant');
const { NotFound } = require('../../utils/errors');

const router = Router();
router.use(requireAuth, requireAdmin);

function callWhere(req) {
  const platformView =
    tenant.isPlatformSuperAdmin(req.user) && req.query.scope === 'platform';
  if (platformView) return { recordingUrl: { not: null } };
  return tenant.scopedWhere(req, { recordingUrl: { not: null } });
}

function meetingWhere(req) {
  const platformView =
    tenant.isPlatformSuperAdmin(req.user) && req.query.scope === 'platform';
  if (platformView) return { recordingUrl: { not: null } };
  return tenant.scopedWhere(req, { recordingUrl: { not: null } });
}

router.get(
  '/',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(50),
      scope: Joi.string().valid('org', 'platform').default('org'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { page, pageSize } = req.query;
    const platformView =
      tenant.isPlatformSuperAdmin(req.user) && req.query.scope === 'platform';

    const [calls, meetings, tenants] = await Promise.all([
      prisma.call.findMany({
        where: callWhere(req),
        include: {
          initiator: { select: { id: true, name: true, tenantId: true } },
          participants: { include: { user: { select: { id: true, name: true } } } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.meetingRoom.findMany({
        where: meetingWhere(req),
        orderBy: { createdAt: 'desc' },
      }),
      platformView
        ? prisma.tenant.findMany({ select: { id: true, name: true, slug: true } })
        : Promise.resolve([]),
    ]);

    const tenantById = new Map(tenants.map((t) => [t.id, t]));

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
        tenantId: c.tenantId,
        organisation: platformView
          ? tenantById.get(c.tenantId) || null
          : undefined,
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
        tenantId: m.tenantId,
        organisation: platformView
          ? tenantById.get(m.tenantId) || null
          : undefined,
      })),
    ].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    const total = items.length;
    const start = (page - 1) * pageSize;
    const pageItems = items.slice(start, start + pageSize);

    res.json({
      items: pageItems,
      total,
      page,
      pageSize,
      scope: platformView ? 'platform' : 'org',
    });
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
    const scoped = tenant.scopedWhere(req, { id, recordingUrl: { not: null } });
    const result = source === 'CALL'
      ? await prisma.call.updateMany({
          where: scoped,
          data: { recordingUrl: null },
        })
      : await prisma.meetingRoom.updateMany({
          where: scoped,
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
