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

function telecallerCallWhere(req) {
  const platformView =
    tenant.isPlatformSuperAdmin(req.user) && req.query.scope === 'platform';
  const base = { recordingUrl: { not: null } };
  if (platformView) return base;
  return {
    ...base,
    agent: { tenantId: tenant.userTenantId(req.user) },
  };
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

    const [calls, meetings, telecallerCalls, tenants] = await Promise.all([
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
      prisma.telecallerCall.findMany({
        where: telecallerCallWhere(req),
        include: {
          lead: { select: { id: true, name: true, phone: true, company: true } },
          agent: { select: { id: true, name: true, tenantId: true } },
        },
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
      ...telecallerCalls.map((tc) => ({
        id: tc.id,
        source: 'TELECALLER',
        title: `Telecaller · ${tc.lead?.name || tc.toNumber || 'Lead'}`,
        recordingUrl: tc.recordingUrl,
        participants: [tc.agent?.name, tc.lead?.name].filter(Boolean),
        startedAt: tc.startedAt,
        endedAt: tc.endedAt,
        createdAt: tc.createdAt,
        tenantId: tc.agent?.tenantId,
        organisation: platformView
          ? tenantById.get(tc.agent?.tenantId) || null
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
      source: Joi.string().valid('CALL', 'MEETING', 'TELECALLER').required(),
      id: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { source, id } = req.params;
    const scoped = tenant.scopedWhere(req, { id, recordingUrl: { not: null } });
    let result;
    if (source === 'CALL') {
      result = await prisma.call.updateMany({
        where: scoped,
        data: { recordingUrl: null },
      });
    } else if (source === 'MEETING') {
      result = await prisma.meetingRoom.updateMany({
        where: scoped,
        data: { recordingUrl: null },
      });
    } else {
      const tcWhere = tenant.isPlatformSuperAdmin(req.user)
        ? { id, recordingUrl: { not: null } }
        : {
            id,
            recordingUrl: { not: null },
            agent: { tenantId: tenant.userTenantId(req.user) },
          };
      result = await prisma.telecallerCall.updateMany({
        where: tcWhere,
        data: { recordingUrl: null },
      });
    }

    if (!result.count) throw NotFound('Recording not found');

    audit.record({
      kind: 'recording.deleted',
      entity: source === 'CALL' ? 'call' : source === 'MEETING' ? 'meeting' : 'telecaller_call',
      entityId: id,
      payload: { source },
      req,
    });
    res.status(204).end();
  })
);

module.exports = router;
