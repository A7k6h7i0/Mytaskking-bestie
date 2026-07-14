'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');
const tenant = require('../../services/tenant');
const mediasoup = require('../../services/mediasoup');
const { NotFound, BadRequest } = require('../../utils/errors');

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

function mediaFilesFromSfu(rec) {
  const files = Array.isArray(rec?.files) ? rec.files : [];
  return files
    .filter((f) => f && (f.url || f.name) && (f.type === 'media' || f.kind || /\.webm$/i.test(String(f.name || ''))))
    .map((f) => {
      const relative =
        f.url ||
        `/api/recordings/${encodeURIComponent(rec.id)}/files/${encodeURIComponent(f.name)}`;
      const kind =
        f.kind ||
        (String(f.name || '').includes('_video_') ? 'video' : 'audio');
      return {
        name: f.name,
        kind,
        participantId: f.participantId || null,
        size: f.size || null,
        url: mediasoup.absoluteRecordingFileUrl(relative),
      };
    });
}

function primaryMediaUrl(files) {
  if (!files.length) return null;
  const audio = files.find((f) => f.kind === 'audio');
  return (audio || files[0]).url;
}

/**
 * Map connect.mytaskking.com SFU recordings (calls.md) into admin list items.
 * Scoped to the org via Call.channelName === roomId when not platform view.
 */
async function buildMediasoupItems(req, { platformView, tenantById }) {
  if (!mediasoup.isConfigured()) return [];

  let sfu;
  try {
    sfu = await mediasoup.listRecordings();
  } catch (err) {
    console.warn('[recordings] mediasoup list failed:', err.message);
    return [];
  }

  const recordings = sfu.recordings || [];
  if (!recordings.length) return [];

  const roomIds = [
    ...new Set(
      recordings
        .map((r) => r.roomId?.toString())
        .filter((id) => id && id.length > 0),
    ),
  ];

  const callWhereClause = platformView
    ? { channelName: { in: roomIds } }
    : tenant.scopedWhere(req, { channelName: { in: roomIds } });

  const matchedCalls = roomIds.length
    ? await prisma.call.findMany({
        where: callWhereClause,
        include: {
          initiator: { select: { id: true, name: true, tenantId: true } },
          participants: {
            include: { user: { select: { id: true, name: true } } },
          },
        },
      })
    : [];

  const callByRoom = new Map(
    matchedCalls.map((c) => [c.channelName, c]),
  );

  const items = [];
  for (const rec of recordings) {
    const roomId = rec.roomId?.toString();
    if (!roomId) continue;
    const call = callByRoom.get(roomId);

    // Org admins only see rooms that belong to their tenant.
    // Platform SUPER_ADMIN sees every connect SFU recording (calls.md).
    const includeUnmatched =
      platformView || tenant.isPlatformSuperAdmin(req.user);
    if (!includeUnmatched && !call) continue;

    const files = mediaFilesFromSfu(rec);
    if (!files.length) continue;

    const participantNames = call
      ? (call.participants || [])
          .map((p) => p.user?.name)
          .filter(Boolean)
      : Array.isArray(rec.participants)
        ? rec.participants.map(String)
        : [];

    const title = call
      ? `${call.kind === 'GROUP' ? 'Group call' : 'Call'} · ${call.initiator?.name || 'Unknown'}`
      : `Call room · ${roomId}`;

    const createdAt =
      rec.startTime || rec.createdAt || call?.createdAt || new Date().toISOString();

    items.push({
      id: String(rec.id),
      source: 'MEDIASOUP',
      title,
      roomId,
      callId: call?.id || null,
      recordingUrl: primaryMediaUrl(files),
      files,
      participants: participantNames,
      startedAt: rec.startTime || call?.startedAt || null,
      endedAt: rec.endTime || call?.endedAt || null,
      createdAt,
      state: rec.state || null,
      size: rec.size || null,
      tenantId: call?.tenantId || call?.initiator?.tenantId || null,
      organisation: platformView
        ? tenantById.get(call?.tenantId || call?.initiator?.tenantId) || null
        : undefined,
    });
  }

  return items;
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

    const [calls, meetings, telecallerCalls, tenants, mediasoupItems] =
      await Promise.all([
        prisma.call.findMany({
          where: callWhere(req),
          include: {
            initiator: { select: { id: true, name: true, tenantId: true } },
            participants: {
              include: { user: { select: { id: true, name: true } } },
            },
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
            lead: {
              select: { id: true, name: true, phone: true, company: true },
            },
            agent: { select: { id: true, name: true, tenantId: true } },
          },
          orderBy: { createdAt: 'desc' },
        }),
        platformView
          ? prisma.tenant.findMany({
              select: { id: true, name: true, slug: true },
            })
          : Promise.resolve([]),
        buildMediasoupItems(req, {
          platformView,
          tenantById: new Map(),
        }),
      ]);

    const tenantById = new Map(tenants.map((t) => [t.id, t]));

    // Re-run mediasoup mapping with tenant names available for platform view.
    const sfuItems =
      platformView && mediasoupItems.length
        ? mediasoupItems.map((item) => ({
            ...item,
            organisation: item.tenantId
              ? tenantById.get(item.tenantId) || null
              : null,
          }))
        : mediasoupItems;

    // Avoid duplicating a call that already has an SFU entry for the same
    // uploaded recordingUrl (legacy client uploads).
    const sfuCallIds = new Set(
      sfuItems.map((i) => i.callId).filter(Boolean),
    );

    const legacyItems = [
      ...calls
        .filter((c) => !sfuCallIds.has(c.id))
        .map((c) => ({
          id: c.id,
          source: 'CALL',
          title: `${c.kind === 'GROUP' ? 'Group call' : 'Call'} · ${c.initiator?.name || 'Unknown'}`,
          recordingUrl: c.recordingUrl,
          files: c.recordingUrl
            ? [{ name: 'recording', kind: 'audio', url: c.recordingUrl }]
            : [],
          participants: (c.participants || [])
            .map((p) => p.user?.name)
            .filter(Boolean),
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
        files: m.recordingUrl
          ? [{ name: 'recording', kind: 'audio', url: m.recordingUrl }]
          : [],
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
        files: tc.recordingUrl
          ? [{ name: 'recording', kind: 'audio', url: tc.recordingUrl }]
          : [],
        participants: [tc.agent?.name, tc.lead?.name].filter(Boolean),
        startedAt: tc.startedAt,
        endedAt: tc.endedAt,
        createdAt: tc.createdAt,
        tenantId: tc.agent?.tenantId,
        organisation: platformView
          ? tenantById.get(tc.agent?.tenantId) || null
          : undefined,
      })),
    ];

    const items = [...sfuItems, ...legacyItems].sort(
      (a, b) => new Date(b.createdAt) - new Date(a.createdAt),
    );

    const total = items.length;
    const start = (page - 1) * pageSize;
    const pageItems = items.slice(start, start + pageSize);

    res.json({
      items: pageItems,
      total,
      page,
      pageSize,
      scope: platformView ? 'platform' : 'org',
      mediasoupConfigured: mediasoup.isConfigured(),
    });
  }),
);

router.delete(
  '/:source/:id',
  validate({
    params: Joi.object({
      source: Joi.string()
        .valid('CALL', 'MEETING', 'TELECALLER', 'MEDIASOUP')
        .required(),
      id: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { source, id } = req.params;

    if (source === 'MEDIASOUP') {
      // Org admins may only delete if the room maps to their tenant call.
      if (!tenant.isPlatformSuperAdmin(req.user)) {
        let sfu;
        try {
          sfu = await mediasoup.listRecordings();
        } catch (err) {
          throw BadRequest(err.message || 'Could not verify recording');
        }
        const rec = (sfu.recordings || []).find((r) => String(r.id) === id);
        if (!rec?.roomId) throw NotFound('Recording not found');
        const call = await prisma.call.findFirst({
          where: tenant.scopedWhere(req, {
            channelName: String(rec.roomId),
          }),
          select: { id: true },
        });
        if (!call) throw NotFound('Recording not found');
      }

      try {
        await mediasoup.deleteRecording(id);
      } catch (err) {
        throw BadRequest(err.message || 'Could not delete SFU recording');
      }

      audit.record({
        kind: 'recording.deleted',
        entity: 'mediasoup_recording',
        entityId: id,
        payload: { source: 'MEDIASOUP' },
        req,
      });
      res.status(204).end();
      return;
    }

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
      entity:
        source === 'CALL'
          ? 'call'
          : source === 'MEETING'
            ? 'meeting'
            : 'telecaller_call',
      entityId: id,
      payload: { source },
      req,
    });
    res.status(204).end();
  }),
);

module.exports = router;
