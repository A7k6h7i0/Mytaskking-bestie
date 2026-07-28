'use strict';

const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const { Forbidden, BadRequest, NotFound } = require('../../utils/errors');
const { getSettings } = require('./employeeTracking.settings');

const TRACKABLE_ROLES = new Set([
  'ADMIN',
  'MANAGER',
  'PROJECT_COORDINATOR_MANAGER',
  'EMPLOYEE',
  'TELECALLER',
  'EXECUTIVE',
  'SALES_HEAD',
]);

const userSelect = {
  id: true,
  name: true,
  userId: true,
  role: true,
  avatarUrl: true,
};

function tenantId(req) {
  return tenant.resolveTenantId(req);
}

function assertOrgAdmin(user) {
  if (user?.role !== 'ADMIN' && user?.role !== 'SUPER_ADMIN') {
    throw Forbidden('Organisation admin only');
  }
}

function isInternalEmployee(user) {
  return user && !user.isClient && TRACKABLE_ROLES.has(user.role);
}

function parseDateKey(value) {
  const text = String(value || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
  return text;
}

function parseTime(value) {
  const text = String(value || '').trim();
  if (!/^\d{2}:\d{2}$/.test(text)) return null;
  return text;
}

function dateKeyInTimeZone(date = new Date(), timeZone = 'Asia/Kolkata') {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
      .formatToParts(date)
      .map((p) => [p.type, p.value])
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${parts.hour}:${parts.minute}`,
  };
}

function isDateInRange(dateKey, fromDate, toDate) {
  const end = toDate || fromDate;
  return dateKey >= fromDate && dateKey <= end;
}

function isTimeInRange(time, startTime, endTime) {
  if (!startTime || !endTime) return true;
  return time >= startTime && time <= endTime;
}

async function isUserOnApprovedLeave(userId, tenantIdValue, at = new Date()) {
  const { date, time } = dateKeyInTimeZone(at);
  const leaves = await prisma.orgLeave.findMany({
    where: {
      tenantId: tenantIdValue,
      userId,
      status: 'APPROVED',
      fromDate: { lte: date },
      OR: [{ toDate: null }, { toDate: { gte: date } }],
    },
  });

  for (const leave of leaves) {
    if (leave.leaveType === 'FULL_DAY') {
      if (isDateInRange(date, leave.fromDate, leave.toDate || leave.fromDate)) {
        return true;
      }
    }
    if (leave.leaveType === 'HALF_DAY') {
      if (!isDateInRange(date, leave.fromDate, leave.toDate || leave.fromDate)) continue;
      if (leave.startTime && leave.endTime) {
        if (isTimeInRange(time, leave.startTime, leave.endTime)) return true;
      } else {
        return true;
      }
    }
    if (leave.leaveType === 'PERMISSION') {
      if (!isDateInRange(date, leave.fromDate, leave.toDate || leave.fromDate)) continue;
      if (leave.startTime && leave.endTime) {
        if (isTimeInRange(time, leave.startTime, leave.endTime)) return true;
      } else if (leave.permissionHours != null) {
        return true;
      }
    }
  }
  return false;
}

async function getTrackingState(req) {
  const settings = await getSettings(req);
  const onLeave = await isUserOnApprovedLeave(req.user.id, tenantId(req));
  const shouldTrack =
    settings.gpsEnabled &&
    isInternalEmployee(req.user) &&
    !onLeave;

  return {
    shouldTrack,
    onApprovedLeave: onLeave,
    gpsEnabled: settings.gpsEnabled,
    intervalSeconds: settings.gpsIntervalSeconds,
  };
}

async function logGps(req, body) {
  if (!isInternalEmployee(req.user)) throw Forbidden('Employees only');
  const onLeave = await isUserOnApprovedLeave(req.user.id, tenantId(req));
  if (onLeave) throw BadRequest('Location tracking is paused during approved leave');

  const lat = Number(body.latitude);
  const lng = Number(body.longitude);
  if (Number.isNaN(lat) || Number.isNaN(lng)) throw BadRequest('latitude and longitude required');

  const row = await prisma.employeeGpsLog.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      latitude: lat,
      longitude: lng,
      accuracy: body.accuracy != null ? Number(body.accuracy) : null,
      loggedAt: body.logged_at ? new Date(body.logged_at) : new Date(),
    },
  });

  return {
    id: row.id,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    accuracy: row.accuracy,
    loggedAt: row.loggedAt,
  };
}

async function listGps(req, query = {}) {
  assertOrgAdmin(req.user);
  const tid = tenantId(req);
  const where = {
    tenantId: tid,
    ...(query.user_id ? { userId: query.user_id } : {}),
    ...(query.from || query.to
      ? {
          loggedAt: {
            ...(query.from ? { gte: new Date(query.from) } : {}),
            ...(query.to ? { lte: new Date(query.to) } : {}),
          },
        }
      : {}),
  };
  const take = Math.min(Number(query.limit) || 100, 500);
  const items = await prisma.employeeGpsLog.findMany({
    where,
    orderBy: { loggedAt: 'desc' },
    take,
    include: { user: { select: userSelect } },
  });
  return items.map((row) => ({
    id: row.id,
    userId: row.userId,
    user: row.user,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    accuracy: row.accuracy,
    loggedAt: row.loggedAt,
  }));
}

async function liveLocations(req) {
  assertOrgAdmin(req.user);
  const tid = tenantId(req);
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const logs = await prisma.employeeGpsLog.findMany({
    where: { tenantId: tid, loggedAt: { gte: since } },
    orderBy: { loggedAt: 'desc' },
    include: { user: { select: userSelect } },
  });

  const latestByUser = new Map();
  for (const log of logs) {
    if (!latestByUser.has(log.userId)) {
      latestByUser.set(log.userId, {
        userId: log.userId,
        user: log.user,
        latitude: Number(log.latitude),
        longitude: Number(log.longitude),
        accuracy: log.accuracy,
        loggedAt: log.loggedAt,
        source: 'gps',
      });
    }
  }

  const activeSessions = await prisma.session.findMany({
    where: {
      status: 'ACTIVE',
      user: { tenantId: tid, isClient: false },
      latitude: { not: null },
      longitude: { not: null },
    },
    orderBy: { firstSeenAt: 'desc' },
    include: { user: { select: userSelect } },
  });

  for (const session of activeSessions) {
    if (!latestByUser.has(session.userId)) {
      latestByUser.set(session.userId, {
        userId: session.userId,
        user: session.user,
        latitude: session.latitude,
        longitude: session.longitude,
        address: session.address,
        loggedAt: session.lastSeenAt || session.firstSeenAt,
        source: 'login',
      });
    }
  }

  return { items: [...latestByUser.values()] };
}

async function createLeave(req, body) {
  if (!isInternalEmployee(req.user)) throw Forbidden('Employees only');
  if (req.user.role === 'ADMIN' || req.user.role === 'SUPER_ADMIN') {
    throw Forbidden('Organisation admins cannot submit leave requests');
  }
  const leaveType = body.leaveType || body.leave_type;
  if (!['FULL_DAY', 'HALF_DAY', 'PERMISSION'].includes(leaveType)) {
    throw BadRequest('Invalid leave type');
  }
  const fromDate = parseDateKey(body.fromDate || body.from_date);
  if (!fromDate) throw BadRequest('fromDate required (YYYY-MM-DD)');
  const toDate = parseDateKey(body.toDate || body.to_date);
  const startTime = parseTime(body.startTime || body.start_time);
  const endTime = parseTime(body.endTime || body.end_time);
  const description = String(body.description || '').trim();
  if (description.length < 5) throw BadRequest('Description required');

  if (leaveType === 'HALF_DAY' && (!startTime || !endTime)) {
    throw BadRequest('Half day leave requires start and end time');
  }
  if (leaveType === 'PERMISSION' && !startTime && !endTime && body.permissionHours == null) {
    throw BadRequest('Permission leave requires time range or permission hours');
  }

  return prisma.orgLeave.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      leaveType,
      fromDate,
      toDate: toDate || (leaveType === 'FULL_DAY' ? fromDate : null),
      startTime,
      endTime,
      permissionHours:
        body.permissionHours != null ? Number(body.permissionHours) : null,
      description,
    },
    include: { user: { select: userSelect } },
  });
}

async function listLeaves(req, query = {}) {
  const tid = tenantId(req);
  const isAdmin = req.user.role === 'ADMIN' || req.user.role === 'SUPER_ADMIN';
  const where = {
    tenantId: tid,
    ...(query.status ? { status: query.status.toUpperCase() } : {}),
    ...(!isAdmin || query.mine === 'true' ? { userId: req.user.id } : {}),
    ...(query.user_id && isAdmin ? { userId: query.user_id } : {}),
  };

  const q = String(query.q || '').trim();
  if (q && isAdmin) {
    where.user = {
      OR: [
        { name: { contains: q, mode: 'insensitive' } },
        { email: { contains: q, mode: 'insensitive' } },
        { userId: { contains: q, mode: 'insensitive' } },
      ],
    };
  }

  const date = String(query.date || '').trim();
  if (date && /^\d{4}-\d{2}-\d{2}$/.test(date) && isAdmin) {
    where.AND = [
      { fromDate: { lte: date } },
      {
        OR: [
          { AND: [{ toDate: null }, { fromDate: date }] },
          { toDate: { gte: date } },
        ],
      },
    ];
  }

  const items = await prisma.orgLeave.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    take: Math.min(Number(query.limit) || 100, 200),
    include: { user: { select: userSelect } },
  });
  return items;
}

async function approveLeave(req, id) {
  assertOrgAdmin(req.user);
  const row = await prisma.orgLeave.findFirst({
    where: { id, tenantId: tenantId(req) },
  });
  if (!row) throw NotFound('Leave request not found');
  if (row.userId === req.user.id) throw Forbidden('Cannot approve your own leave');
  if (row.status !== 'PENDING') throw BadRequest('Leave already reviewed');
  return prisma.orgLeave.update({
    where: { id },
    data: {
      status: 'APPROVED',
      approvedById: req.user.id,
      approvedAt: new Date(),
    },
    include: { user: { select: userSelect } },
  });
}

async function rejectLeave(req, id, body) {
  assertOrgAdmin(req.user);
  const row = await prisma.orgLeave.findFirst({
    where: { id, tenantId: tenantId(req) },
  });
  if (!row) throw NotFound('Leave request not found');
  if (row.userId === req.user.id) throw Forbidden('Cannot reject your own leave');
  if (row.status !== 'PENDING') throw BadRequest('Leave already reviewed');
  return prisma.orgLeave.update({
    where: { id },
    data: {
      status: 'REJECTED',
      approvedById: req.user.id,
      approvedAt: new Date(),
      rejectionReason: body.reason?.trim() || null,
    },
    include: { user: { select: userSelect } },
  });
}

module.exports = {
  getTrackingState,
  logGps,
  listGps,
  liveLocations,
  createLeave,
  listLeaves,
  approveLeave,
  rejectLeave,
  isUserOnApprovedLeave,
  getSettings,
};
