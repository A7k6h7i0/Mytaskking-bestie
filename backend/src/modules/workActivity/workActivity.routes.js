'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin, requireInternal } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const audit = require('../../services/audit');
const { Forbidden } = require('../../utils/errors');

const router = Router();
router.use(requireAuth);

const TRACKABLE_ROLES = new Set([
  'MANAGER',
  'PROJECT_COORDINATOR_MANAGER',
  'EMPLOYEE',
  'TELECALLER',
]);
const TRACK_INTERVAL_OPTIONS = [120, 300, 900, 1800, 3600];
const DEFAULT_TRACK_INTERVAL_SECONDS = 300;

function normalizedNote(value) {
  const text = String(value || '').trim();
  return text || 'working';
}

function localDateKey(date = new Date(), timeZone = 'Asia/Kolkata') {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(date).map((part) => [part.type, part.value])
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function localDateRange(dateKey) {
  const start = new Date(`${dateKey}T00:00:00.000+05:30`);
  return {
    start,
    end: new Date(start.getTime() + 24 * 60 * 60 * 1000),
  };
}

function workSeconds(entry, now = new Date()) {
  if (!entry?.checkInAt) return 0;
  const end = entry.checkOutAt || now;
  let seconds = Math.max(0, Math.round((end.getTime() - entry.checkInAt.getTime()) / 1000));
  if (entry.lunchStartedAt) {
    const lunchEnd = entry.lunchEndedAt || end;
    seconds -= Math.max(0, Math.round((lunchEnd.getTime() - entry.lunchStartedAt.getTime()) / 1000));
  }
  seconds -= entry.breakSeconds || 0;
  return Math.max(0, seconds);
}

function availabilityFromPresence(presence) {
  const custom = String(presence?.customStatus || '').toLowerCase();
  if (custom.includes('lunch')) return 'LUNCH';
  if (custom.includes('leave')) return 'LEAVE';
  if (custom.includes('busy')) return 'BUSY';
  if (presence?.status && presence.status !== 'ACTIVE') return presence.status;
  return 'WORKING';
}

function shouldTrack({ user, presence }) {
  if (!TRACKABLE_ROLES.has(user.role)) return false;
  return availabilityFromPresence(presence) === 'WORKING';
}

async function workActivityIntervalSeconds() {
  const row = await prisma.workspaceSetting.findUnique({
    where: {
      scope_key: {
        scope: 'workActivity',
        key: 'intervalSeconds',
      },
    },
    select: { value: true },
  });
  const configured = Number(row?.value);
  return TRACK_INTERVAL_OPTIONS.includes(configured)
    ? configured
    : DEFAULT_TRACK_INTERVAL_SECONDS;
}

router.get(
  '/me/state',
  requireInternal,
  asyncHandler(async (req, res) => {
    const intervalSeconds = await workActivityIntervalSeconds();
    const presence = await prisma.userPresence.findUnique({
      where: { userId: req.user.id },
    });
    const availability = availabilityFromPresence(presence);
    res.json({
      shouldTrack: shouldTrack({ user: req.user, presence }),
      availability,
      intervalSeconds,
      captureSeconds: 5,
      promptSeconds: 30,
      platform: 'desktop',
    });
  })
);

router.post(
  '/clips',
  requireInternal,
  validate({
    body: Joi.object({
      fileId: Joi.string().allow('', null),
      clipUrl: Joi.string().uri().allow('', null),
      note: Joi.string().max(1000).allow('', null),
      status: Joi.string().max(48).default('WORKING'),
      platform: Joi.string().valid('windows', 'linux').required(),
      deviceLabel: Joi.string().max(120).allow('', null),
      durationSeconds: Joi.number().integer().min(0).max(30).default(5),
      captureStartedAt: Joi.date().iso().allow(null),
      captureEndedAt: Joi.date().iso().allow(null),
      promptShownAt: Joi.date().iso().allow(null),
      promptRespondedAt: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    if (!TRACKABLE_ROLES.has(req.user.role)) throw Forbidden('Work activity is employee-only');
    let clipUrl = req.body.clipUrl || null;
    if (req.body.fileId) {
      const asset = await prisma.fileAsset.findUnique({
        where: { id: req.body.fileId },
        select: { id: true, url: true, uploadedById: true },
      });
      if (asset && asset.uploadedById === req.user.id) clipUrl = asset.url;
    }
    const clip = await prisma.workActivityClip.create({
      data: tenant.withTenant(req, {
        userId: req.user.id,
        fileId: req.body.fileId || null,
        clipUrl,
        note: normalizedNote(req.body.note),
        status: req.body.status || 'WORKING',
        platform: req.body.platform,
        deviceLabel: req.body.deviceLabel || null,
        durationSeconds: req.body.durationSeconds,
        captureStartedAt: req.body.captureStartedAt ? new Date(req.body.captureStartedAt) : new Date(),
        captureEndedAt: req.body.captureEndedAt ? new Date(req.body.captureEndedAt) : null,
        promptShownAt: req.body.promptShownAt ? new Date(req.body.promptShownAt) : null,
        promptRespondedAt: req.body.promptRespondedAt ? new Date(req.body.promptRespondedAt) : null,
      }),
    });
    audit.record({ kind: 'work_activity.clip_created', entity: 'work_activity', entityId: clip.id, req });
    req.app.get('io')?.to('role:ADMIN').to('role:SUPER_ADMIN').emit('work_activity.clip_created', clip);
    res.status(201).json(clip);
  })
);

router.get(
  '/summary',
  requireAdmin,
  validate({
    query: Joi.object({
      date: Joi.string().allow('', null),
      timezone: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const date = req.query.date || localDateKey(new Date(), req.query.timezone || 'Asia/Kolkata');
    const { start, end } = localDateRange(date);
    const intervalSeconds = await workActivityIntervalSeconds();
    const users = await prisma.user.findMany({
      where: tenant.scopedWhere(req, {
        isClient: false,
        status: 'ACTIVE',
        role: { in: Array.from(TRACKABLE_ROLES) },
      }),
      orderBy: { name: 'asc' },
      select: { id: true, name: true, userId: true, role: true, avatarUrl: true, customTitle: true },
    });
    const userIds = users.map((u) => u.id);
    const [presenceRows, workdayRows, clips] = await Promise.all([
      prisma.userPresence.findMany({ where: { userId: { in: userIds } } }),
      prisma.workdayLog.findMany({ where: { userId: { in: userIds }, localDate: date } }),
      prisma.workActivityClip.findMany({
        where: tenant.scopedWhere(req, {
          userId: { in: userIds },
          captureStartedAt: { gte: start, lt: end },
        }),
        orderBy: { captureStartedAt: 'desc' },
        take: 250,
      }),
    ]);
    const presenceByUser = new Map(presenceRows.map((p) => [p.userId, p]));
    const workdayByUser = new Map(workdayRows.map((w) => [w.userId, w]));
    const latestByUser = new Map();
    const counts = new Map();
    const activitySecondsByUser = new Map();
    for (const clip of clips) {
      counts.set(clip.userId, (counts.get(clip.userId) || 0) + 1);
      if (!latestByUser.has(clip.userId)) latestByUser.set(clip.userId, clip);
      if (clip.promptRespondedAt && clip.status !== 'CAPTURE_FAILED') {
        activitySecondsByUser.set(
          clip.userId,
          (activitySecondsByUser.get(clip.userId) || 0) + intervalSeconds
        );
      }
    }
    res.json({
      date,
      items: users.map((user) => {
        const presence = presenceByUser.get(user.id);
        const availability = availabilityFromPresence(presence);
        return {
          user,
          availability,
          status: shouldTrack({ user, presence }) ? 'Working' : availability,
          workingSeconds: Math.max(
            workSeconds(workdayByUser.get(user.id)),
            activitySecondsByUser.get(user.id) || 0
          ),
          clipCount: counts.get(user.id) || 0,
          latestClip: latestByUser.get(user.id) || null,
        };
      }),
    });
  })
);

router.get(
  '/users/:userId/clips',
  requireAdmin,
  validate({
    query: Joi.object({
      from: Joi.date().iso().allow(null),
      to: Joi.date().iso().allow(null),
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(50),
    }),
  }),
  asyncHandler(async (req, res) => {
    await tenant.assertUserSameTenant(req, req.params.userId);
    const page = Number(req.query.page || 1);
    const pageSize = Number(req.query.pageSize || 50);
    const where = tenant.scopedWhere(req, {
      userId: req.params.userId,
      ...(req.query.from || req.query.to
        ? {
            captureStartedAt: {
              ...(req.query.from ? { gte: new Date(req.query.from) } : {}),
              ...(req.query.to ? { lte: new Date(req.query.to) } : {}),
            },
          }
        : {}),
    });
    const [total, items] = await prisma.$transaction([
      prisma.workActivityClip.count({ where }),
      prisma.workActivityClip.findMany({
        where,
        orderBy: { captureStartedAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
    ]);
    res.json({ total, page, pageSize, items });
  })
);

module.exports = router;
