'use strict';

const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const { Forbidden, NotFound } = require('../../utils/errors');

const DEFAULT_TIMEZONE = process.env.WORKDAY_TIMEZONE || 'Asia/Kolkata';

const MANAGER_VIEWER_ROLES = new Set(['MANAGER', 'PROJECT_COORDINATOR_MANAGER']);
const ADMIN_VIEWER_ROLES = new Set(['ADMIN', 'SUPER_ADMIN']);
const MANAGER_WORKDAY_ROLES = new Set(['MANAGER', 'PROJECT_COORDINATOR_MANAGER', 'ADMIN', 'SUPER_ADMIN']);

function normalizeTimezone(value) {
  const candidate = String(value || DEFAULT_TIMEZONE).trim() || DEFAULT_TIMEZONE;
  try {
    Intl.DateTimeFormat('en-US', { timeZone: candidate }).format(new Date());
    return candidate;
  } catch {
    return DEFAULT_TIMEZONE;
  }
}

function localDateKey(date = new Date(), timeZone = DEFAULT_TIMEZONE) {
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

function isAdminViewer(user) {
  return ADMIN_VIEWER_ROLES.has(user?.role);
}

function isManagerViewer(user) {
  return MANAGER_VIEWER_ROLES.has(user?.role);
}

function canViewSummary(user) {
  return isAdminViewer(user) || isManagerViewer(user);
}

function canViewUserWorkday(viewer, subject) {
  if (!subject) return false;
  if (subject.isClient === true) return false;
  if (subject.status != null && subject.status !== 'ACTIVE') return false;
  if (isAdminViewer(viewer)) return true;
  if (!isManagerViewer(viewer)) return false;
  return !MANAGER_WORKDAY_ROLES.has(subject.role);
}

function serializeEntry(entry) {
  if (!entry) {
    return {
      status: 'PENDING',
      lunchState: 'NOT_STARTED',
      onBreak: false,
      breakSeconds: 0,
    };
  }
  const lunchState = entry.lunchStartedAt && !entry.lunchEndedAt
    ? 'ON_BREAK_LUNCH'
    : entry.lunchStartedAt && entry.lunchEndedAt
      ? 'COMPLETED'
      : 'NOT_STARTED';
  const status = entry.checkOutAt
    ? 'CHECKED_OUT'
    : entry.lunchStartedAt && !entry.lunchEndedAt
      ? 'AT_LUNCH'
      : entry.checkInAt
        ? 'CHECKED_IN'
        : 'PENDING';

  return {
    id: entry.id,
    userId: entry.userId,
    localDate: entry.localDate,
    timezone: entry.timezone,
    status,
    lunchState,
    checkInAt: entry.checkInAt,
    checkInPlan: entry.checkInPlan,
    checkInWordCount: entry.checkInWordCount,
    lunchStartedAt: entry.lunchStartedAt,
    lunchEndedAt: entry.lunchEndedAt,
    lunchNote: entry.lunchNote,
    checkOutAt: entry.checkOutAt,
    checkOutReport: entry.checkOutReport,
    checkOutWordCount: entry.checkOutWordCount,
    onBreakSince: entry.onBreakSince,
    onBreak: entry.onBreakSince != null,
    breakSeconds: entry.breakSeconds || 0,
  };
}

function displayStatus(entry) {
  const serialized = serializeEntry(entry);
  if (serialized.status === 'CHECKED_OUT') return 'Logged out';
  if (serialized.status === 'AT_LUNCH') return 'Lunch';
  if (serialized.onBreak) return 'Break';
  if (serialized.status === 'CHECKED_IN') return 'Checked in';
  return 'Not started';
}

async function getSummary(req, { date, timezone }) {
  if (!canViewSummary(req.user)) throw Forbidden('Managers and admins only');

  const tz = normalizeTimezone(timezone);
  const dateKey = date || localDateKey(new Date(), tz);

  const users = await prisma.user.findMany({
    where: tenant.scopedWhere(req, {
      isClient: false,
      status: 'ACTIVE',
    }),
    orderBy: { name: 'asc' },
    select: {
      id: true,
      name: true,
      userId: true,
      role: true,
      status: true,
      isClient: true,
      avatarUrl: true,
      customTitle: true,
    },
  });

  const visibleUsers = users.filter((user) => canViewUserWorkday(req.user, user));
  const userIds = visibleUsers.map((user) => user.id);
  const logs = userIds.length
    ? await prisma.workdayLog.findMany({
        where: { userId: { in: userIds }, localDate: dateKey },
      })
    : [];
  const logByUser = new Map(logs.map((log) => [log.userId, log]));

  return {
    date: dateKey,
    timezone: tz,
    viewerRole: req.user.role,
    items: visibleUsers.map((user) => {
      const entry = logByUser.get(user.id) || null;
      const serialized = serializeEntry(entry);
      return {
        user,
        entry: serialized,
        status: displayStatus(entry),
        statusCode: serialized.status,
        onBreak: serialized.onBreak,
      };
    }),
  };
}

async function getUserDay(req, userId, { date, timezone }) {
  if (!canViewSummary(req.user)) throw Forbidden('Managers and admins only');

  const subject = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      name: true,
      userId: true,
      role: true,
      avatarUrl: true,
      customTitle: true,
      isClient: true,
      status: true,
      tenantId: true,
    },
  });
  if (!subject) throw NotFound('User not found');
  await tenant.assertUserSameTenant(req, userId);
  if (!canViewUserWorkday(req.user, subject)) {
    throw Forbidden('You cannot view this employee\'s workday');
  }

  const tz = normalizeTimezone(timezone);
  const dateKey = date || localDateKey(new Date(), tz);
  const entry = await prisma.workdayLog.findUnique({
    where: { userId_localDate: { userId, localDate: dateKey } },
  });

  return {
    date: dateKey,
    timezone: tz,
    user: subject,
    entry: serializeEntry(entry),
    status: displayStatus(entry),
  };
}

module.exports = {
  canViewSummary,
  canViewUserWorkday,
  getSummary,
  getUserDay,
  serializeEntry,
  displayStatus,
  localDateKey,
};
