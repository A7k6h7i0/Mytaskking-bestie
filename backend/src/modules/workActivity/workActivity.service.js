'use strict';

const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const { Forbidden, NotFound } = require('../../utils/errors');

const TRACKABLE_ROLES = new Set([
  'MANAGER',
  'PROJECT_COORDINATOR_MANAGER',
  'EMPLOYEE',
  'TELECALLER',
]);
const TRACK_INTERVAL_OPTIONS = [120, 300, 900, 1800, 3600];

function localDateKey(date = new Date(), timeZone = 'Asia/Kolkata') {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    })
      .formatToParts(date)
      .map((part) => [part.type, part.value])
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

function normalizedNote(value) {
  const text = String(value || '').trim();
  return text || 'working';
}

async function workActivityIntervalSeconds(req) {
  const scopes = [];
  if (req) scopes.push(tenant.orgSettingScope(req, 'workActivity'));
  if (!scopes.includes('workActivity')) scopes.push('workActivity');

  for (const scope of scopes) {
    const row = await prisma.workspaceSetting.findUnique({
      where: { scope_key: { scope, key: 'intervalSeconds' } },
      select: { value: true },
    });
    const configured = Number(row?.value);
    if (TRACK_INTERVAL_OPTIONS.includes(configured)) return configured;
  }
  return null;
}

function formatDisplayStatus(raw) {
  const text = String(raw || 'OFFLINE').toUpperCase();
  if (text === 'WORKING') return 'Working';
  if (text === 'PAUSED' || text === 'IDLE') return 'Idle';
  if (text === 'OFFLINE') return 'Offline';
  if (text === 'LUNCH') return 'Lunch';
  if (text === 'BUSY') return 'Busy';
  if (text === 'LEAVE') return 'Leave';
  return text.charAt(0) + text.slice(1).toLowerCase();
}

function presenceDisplayStatus(presence) {
  const availability = availabilityFromPresence(presence);
  if (availability === 'WORKING') return null;
  return formatDisplayStatus(availability);
}

function secondsSince(date, now = new Date()) {
  if (!date) return null;
  return Math.max(0, Math.floor((now.getTime() - new Date(date).getTime()) / 1000));
}

function accumulateActiveWorkSeconds(day, intervalSeconds, now = new Date()) {
  if (!day || day.pausedAt) return 0;
  const anchor = day.lastHeartbeatAt || day.desktopLoginAt;
  if (!anchor) return 0;
  const elapsed = secondsSince(anchor, now);
  if (elapsed <= 0) return 0;
  return Math.min(elapsed, intervalSeconds);
}

function resolveLiveStatus(day, presence, intervalSeconds, now = new Date()) {
  const blocked = presenceDisplayStatus(presence);
  if (blocked) return blocked.toUpperCase() === 'LUNCH' ? 'LUNCH' : blocked.toUpperCase();

  if (!day?.desktopLoginAt) return 'OFFLINE';
  if (day.pausedAt) return 'PAUSED';

  const staleAfter = intervalSeconds * 2;
  const sinceBeat = secondsSince(day.lastHeartbeatAt || day.desktopLoginAt, now);
  if (sinceBeat != null && sinceBeat > staleAfter) return 'OFFLINE';

  return day.activityStatus === 'WORKING' ? 'WORKING' : day.activityStatus || 'OFFLINE';
}

async function ensureDayForUser(req, userId, dateKey) {
  return prisma.workActivityDay.upsert({
    where: { userId_localDate: { userId, localDate: dateKey } },
    update: {},
    create: tenant.withTenant(req, {
      userId,
      localDate: dateKey,
      activityStatus: 'OFFLINE',
    }),
  });
}

async function getStateForUser(req) {
  const intervalSeconds = await workActivityIntervalSeconds(req);
  const presence = await prisma.userPresence.findUnique({
    where: { userId: req.user.id },
  });
  const availability = availabilityFromPresence(presence);
  const trackable = shouldTrack({ user: req.user, presence });
  return {
    shouldTrack: trackable && intervalSeconds != null,
    availability,
    intervalSeconds,
    captureSeconds: 5,
    promptSeconds: 30,
    platform: 'desktop',
    trackingConfigured: intervalSeconds != null,
  };
}

async function registerDesktopSession(req, body) {
  if (!TRACKABLE_ROLES.has(req.user.role)) throw Forbidden('Work activity is employee-only');
  const dateKey = localDateKey(new Date(), 'Asia/Kolkata');
  const now = new Date();
  const existing = await prisma.workActivityDay.findUnique({
    where: { userId_localDate: { userId: req.user.id, localDate: dateKey } },
  });

  const data = {
    lastHeartbeatAt: now,
    pausedAt: null,
    activityStatus: 'WORKING',
    sessionId: body.sessionId || existing?.sessionId || null,
  };

  if (!existing?.desktopLoginAt) {
    data.desktopLoginAt = now;
    data.lastConfirmedAt = now;
  }

  if (body.latitude != null && existing?.loginLatitude == null) {
    data.loginLatitude = Number(body.latitude);
  }
  if (body.longitude != null && existing?.loginLongitude == null) {
    data.loginLongitude = Number(body.longitude);
  }
  if (body.address && !existing?.loginAddress) {
    data.loginAddress = String(body.address).trim() || null;
  }

  const day = await prisma.workActivityDay.upsert({
    where: { userId_localDate: { userId: req.user.id, localDate: dateKey } },
    update: data,
    create: tenant.withTenant(req, {
      userId: req.user.id,
      localDate: dateKey,
      desktopLoginAt: now,
      lastConfirmedAt: now,
      loginLatitude: body.latitude != null ? Number(body.latitude) : null,
      loginLongitude: body.longitude != null ? Number(body.longitude) : null,
      loginAddress: body.address ? String(body.address).trim() || null : null,
      sessionId: body.sessionId || null,
      ...data,
    }),
  });
  return day;
}

async function processHeartbeat(req, body) {
  if (!TRACKABLE_ROLES.has(req.user.role)) throw Forbidden('Work activity is employee-only');
  const intervalSeconds = await workActivityIntervalSeconds(req);
  const presence = await prisma.userPresence.findUnique({
    where: { userId: req.user.id },
  });
  const availability = availabilityFromPresence(presence);
  const trackable = shouldTrack({ user: req.user, presence });
  const now = new Date();
  const dateKey = localDateKey(now, 'Asia/Kolkata');
  const idleSeconds = Math.max(0, Number(body.idleSeconds) || 0);

  if (!intervalSeconds) {
    return {
      intervalSeconds: null,
      shouldTrack: false,
      availability,
      shouldCapture: false,
      trackingConfigured: false,
      workingSeconds: 0,
      activityStatus: 'OFFLINE',
    };
  }

  let day = await prisma.workActivityDay.findUnique({
    where: { userId_localDate: { userId: req.user.id, localDate: dateKey } },
  });

  if (!trackable) {
    if (day) {
      day = await prisma.workActivityDay.update({
        where: { id: day.id },
        data: {
          activityStatus: availability === 'WORKING' ? 'OFFLINE' : availability,
          pausedAt: null,
        },
      });
    }
    return {
      intervalSeconds,
      shouldTrack: false,
      availability,
      shouldCapture: false,
      trackingConfigured: true,
      workingSeconds: day?.workingSeconds || 0,
      activityStatus: day?.activityStatus || availability,
    };
  }

  if (!day?.desktopLoginAt) {
    day = await registerDesktopSession(req, {
      sessionId: body.sessionId || null,
    });
  }

  let shouldCapture = false;
  const update = { lastHeartbeatAt: now };

  if (day.pausedAt) {
    shouldCapture = true;
    update.activityStatus = 'PAUSED';
  } else if (idleSeconds >= intervalSeconds) {
    shouldCapture = true;
    update.pausedAt = now;
    update.activityStatus = 'IDLE';
  } else {
    const addSeconds = accumulateActiveWorkSeconds(day, intervalSeconds, now);
    update.workingSeconds = (day.workingSeconds || 0) + addSeconds;
    update.activityStatus = 'WORKING';
    update.pausedAt = null;
    update.lastConfirmedAt = now;
  }

  day = await prisma.workActivityDay.update({
    where: { id: day.id },
    data: update,
  });

  return {
    intervalSeconds,
    shouldTrack: true,
    availability,
    shouldCapture,
    captureSeconds: 5,
    promptSeconds: 30,
    trackingConfigured: true,
    workingSeconds: day.workingSeconds,
    activityStatus: day.activityStatus,
  };
}

async function confirmAfterPrompt(req) {
  const dateKey = localDateKey(new Date(), 'Asia/Kolkata');
  const day = await prisma.workActivityDay.findUnique({
    where: { userId_localDate: { userId: req.user.id, localDate: dateKey } },
  });
  if (!day) return null;
  const now = new Date();
  return prisma.workActivityDay.update({
    where: { id: day.id },
    data: {
      pausedAt: null,
      lastConfirmedAt: now,
      lastHeartbeatAt: now,
      activityStatus: 'WORKING',
    },
  });
}

async function createClip(req, body) {
  if (!TRACKABLE_ROLES.has(req.user.role)) throw Forbidden('Work activity is employee-only');
  let clipUrl = body.clipUrl || null;
  if (body.fileId) {
    const asset = await prisma.fileAsset.findUnique({
      where: { id: body.fileId },
      select: { id: true, url: true, uploadedById: true },
    });
    if (asset && asset.uploadedById === req.user.id) clipUrl = asset.url;
  }
  const clip = await prisma.workActivityClip.create({
    data: tenant.withTenant(req, {
      userId: req.user.id,
      fileId: body.fileId || null,
      clipUrl,
      note: normalizedNote(body.note),
      status: body.status || 'WORKING',
      platform: body.platform,
      deviceLabel: body.deviceLabel || null,
      durationSeconds: body.durationSeconds,
      captureStartedAt: body.captureStartedAt ? new Date(body.captureStartedAt) : new Date(),
      captureEndedAt: body.captureEndedAt ? new Date(body.captureEndedAt) : null,
      promptShownAt: body.promptShownAt ? new Date(body.promptShownAt) : null,
      promptRespondedAt: body.promptRespondedAt ? new Date(body.promptRespondedAt) : null,
    }),
  });
  if (body.promptRespondedAt) {
    await confirmAfterPrompt(req);
  }
  return clip;
}

async function getSummary(req, { date, timezone = 'Asia/Kolkata' }) {
  const dateKey = date || localDateKey(new Date(), timezone);
  const intervalSeconds = await workActivityIntervalSeconds(req);
  const { start, end } = localDateRange(dateKey);
  const now = new Date();

  const days = await prisma.workActivityDay.findMany({
    where: tenant.scopedWhere(req, {
      localDate: dateKey,
      desktopLoginAt: { not: null },
    }),
    include: {
      user: {
        select: {
          id: true,
          name: true,
          userId: true,
          role: true,
          avatarUrl: true,
          customTitle: true,
        },
      },
    },
    orderBy: { desktopLoginAt: 'asc' },
  });

  const userIds = days.map((d) => d.userId);
  const [presenceRows, clips] = await Promise.all([
    prisma.userPresence.findMany({ where: { userId: { in: userIds } } }),
    prisma.workActivityClip.findMany({
      where: tenant.scopedWhere(req, {
        userId: { in: userIds },
        captureStartedAt: { gte: start, lt: end },
      }),
      orderBy: { captureStartedAt: 'desc' },
    }),
  ]);

  const presenceByUser = new Map(presenceRows.map((p) => [p.userId, p]));
  const counts = new Map();
  const latestByUser = new Map();
  for (const clip of clips) {
    counts.set(clip.userId, (counts.get(clip.userId) || 0) + 1);
    if (!latestByUser.has(clip.userId)) latestByUser.set(clip.userId, clip);
  }

  return {
    date: dateKey,
    intervalSeconds,
    items: days.map((day) => {
      const presence = presenceByUser.get(day.userId);
      const liveStatus = resolveLiveStatus(day, presence, intervalSeconds || 300, now);
      const blocked = presenceDisplayStatus(presence);
      return {
        user: day.user,
        availability: availabilityFromPresence(presence),
        status: formatDisplayStatus(blocked || liveStatus),
        workingSeconds: day.workingSeconds || 0,
        clipCount: counts.get(day.userId) || 0,
        latestClip: latestByUser.get(day.userId) || null,
        desktopLoginAt: day.desktopLoginAt,
        loginAddress: day.loginAddress,
        loginLatitude: day.loginLatitude,
        loginLongitude: day.loginLongitude,
        activityStatus: liveStatus,
      };
    }),
  };
}

async function getUserDay(req, userId, { date, timezone = 'Asia/Kolkata' }) {
  await tenant.assertUserSameTenant(req, userId);
  const dateKey = date || localDateKey(new Date(), timezone);
  const intervalSeconds = await workActivityIntervalSeconds(req);
  const day = await prisma.workActivityDay.findUnique({
    where: { userId_localDate: { userId, localDate: dateKey } },
    include: {
      user: {
        select: {
          id: true,
          name: true,
          userId: true,
          role: true,
          avatarUrl: true,
          customTitle: true,
        },
      },
    },
  });
  if (!day) throw NotFound('No desktop work activity for this date');

  const presence = await prisma.userPresence.findUnique({ where: { userId } });
  const now = new Date();
  const liveStatus = resolveLiveStatus(day, presence, intervalSeconds || 300, now);
  const blocked = presenceDisplayStatus(presence);

  return {
    date: dateKey,
    intervalSeconds,
    user: day.user,
    desktopLoginAt: day.desktopLoginAt,
    loginAddress: day.loginAddress,
    loginLatitude: day.loginLatitude,
    loginLongitude: day.loginLongitude,
    workingSeconds: day.workingSeconds || 0,
    status: formatDisplayStatus(blocked || liveStatus),
    activityStatus: liveStatus,
    availability: availabilityFromPresence(presence),
    lastHeartbeatAt: day.lastHeartbeatAt,
    lastConfirmedAt: day.lastConfirmedAt,
    pausedAt: day.pausedAt,
  };
}

module.exports = {
  TRACKABLE_ROLES,
  TRACK_INTERVAL_OPTIONS,
  localDateKey,
  getStateForUser,
  registerDesktopSession,
  processHeartbeat,
  createClip,
  getSummary,
  getUserDay,
  workActivityIntervalSeconds,
};
