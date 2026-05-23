'use strict';

const { Router } = require('express');
const Joi = require('joi');
const prisma = require('../../database/prisma');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireInternal } = require('../../middleware/auth');
const { BadRequest, Conflict } = require('../../utils/errors');

const router = Router();
router.use(requireAuth, requireInternal);

const DEFAULT_TIMEZONE = process.env.WORKDAY_TIMEZONE || 'Asia/Kolkata';
const DEFAULT_CONFIG = {
  minRequiredWords: 100,
  checkInHour: 9,
  lunchStartHour: 13,
  lunchEndHour: 14,
  checkOutHour: 18,
};

function normalizeTimezone(value) {
  const candidate = String(value || DEFAULT_TIMEZONE).trim() || DEFAULT_TIMEZONE;
  try {
    Intl.DateTimeFormat('en-US', { timeZone: candidate }).format(new Date());
    return candidate;
  } catch {
    return DEFAULT_TIMEZONE;
  }
}

function localParts(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });

  const parts = Object.fromEntries(
    formatter.formatToParts(date).map((part) => [part.type, part.value])
  );

  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
    dateKey: `${parts.year}-${parts.month}-${parts.day}`,
  };
}

function parseWordCount(text) {
  return String(text || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .length;
}

function ensureMinimumWords(text, label) {
  const count = parseWordCount(text);
  return count;
}

function ensureMinimumWordsWithConfig(text, label, minRequiredWords) {
  const count = parseWordCount(text);
  if (count < minRequiredWords) {
    throw BadRequest(`${label} must be at least ${minRequiredWords} words`, {
      words: count,
      required: minRequiredWords,
    });
  }
  return count;
}

async function getAttendanceConfig() {
  const rows = await prisma.workspaceSetting.findMany({
    where: { scope: 'attendance' },
  });
  const map = Object.fromEntries(rows.map((row) => [row.key, row.value]));
  return {
    minRequiredWords: Number(map.minRequiredWords ?? DEFAULT_CONFIG.minRequiredWords),
    checkInHour: Number(map.checkInHour ?? DEFAULT_CONFIG.checkInHour),
    lunchStartHour: Number(map.lunchStartHour ?? DEFAULT_CONFIG.lunchStartHour),
    lunchEndHour: Number(map.lunchEndHour ?? DEFAULT_CONFIG.lunchEndHour),
    checkOutHour: Number(map.checkOutHour ?? DEFAULT_CONFIG.checkOutHour),
  };
}

function serializeEntry(entry) {
  if (!entry) return null;
  const lunchState = entry.lunchStartedAt && !entry.lunchEndedAt
    ? 'ON_BREAK'
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
  };
}

async function getOrCreateTodayLog(userId, timeZone) {
  const now = new Date();
  const parts = localParts(now, timeZone);
  const entry = await prisma.workdayLog.upsert({
    where: { userId_localDate: { userId, localDate: parts.dateKey } },
    update: {},
    create: { userId, localDate: parts.dateKey, timezone: timeZone },
  });
  return { entry, local: parts, now };
}

router.get(
  '/today',
  validate({ query: Joi.object({ timezone: Joi.string().allow('', null) }) }),
  asyncHandler(async (req, res) => {
    const timezone = normalizeTimezone(req.query.timezone);
    const config = await getAttendanceConfig();
    const { entry, local } = await getOrCreateTodayLog(req.user.id, timezone);
    res.json({
      timezone,
      today: local.dateKey,
      opensAt: { hour: config.checkInHour, minute: 0 },
      lunchWindow: { startHour: config.lunchStartHour, endHour: config.lunchEndHour },
      checkOutAt: { hour: config.checkOutHour, minute: 0 },
      currentLocalTime: `${String(local.hour).padStart(2, '0')}:${String(local.minute).padStart(2, '0')}`,
      minRequiredWords: config.minRequiredWords,
      entry: serializeEntry(entry),
    });
  })
);

router.get(
  '/range',
  validate({
    query: Joi.object({
      from: Joi.date().iso().required(),
      to: Joi.date().iso().required(),
      timezone: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const timezone = normalizeTimezone(req.query.timezone);
    const fromDate = localParts(new Date(req.query.from), timezone).dateKey;
    const toDate = localParts(new Date(req.query.to), timezone).dateKey;
    const items = await prisma.workdayLog.findMany({
      where: { userId: req.user.id, localDate: { gte: fromDate, lte: toDate } },
      orderBy: { localDate: 'asc' },
    });

    res.json({
      timezone,
      from: fromDate,
      to: toDate,
      minRequiredWords: (await getAttendanceConfig()).minRequiredWords,
      items: items.map(serializeEntry),
    });
  })
);

router.post(
  '/check-in',
  validate({ body: Joi.object({ plan: Joi.string().min(1).max(10000).required(), timezone: Joi.string().allow('', null) }) }),
  asyncHandler(async (req, res) => {
    const timezone = normalizeTimezone(req.body.timezone);
    const config = await getAttendanceConfig();
    const wordCount = ensureMinimumWordsWithConfig(req.body.plan, 'Daily plan', config.minRequiredWords);
    const { entry, local, now } = await getOrCreateTodayLog(req.user.id, timezone);

    if (local.hour < config.checkInHour) {
      throw BadRequest(`Check-in opens at ${String(config.checkInHour).padStart(2, '0')}:00`, { timezone, currentHour: local.hour });
    }
    if (entry.checkInAt) throw Conflict('You have already checked in for today');

    const updated = await prisma.workdayLog.update({
      where: { id: entry.id },
      data: {
        timezone,
        checkInAt: now,
        checkInPlan: req.body.plan.trim(),
        checkInWordCount: wordCount,
      },
    });

    res.json({ ok: true, entry: serializeEntry(updated) });
  })
);

router.post(
  '/lunch',
  validate({ body: Joi.object({ note: Joi.string().allow('', null).max(5000), timezone: Joi.string().allow('', null) }) }),
  asyncHandler(async (req, res) => {
    const timezone = normalizeTimezone(req.body.timezone);
    const config = await getAttendanceConfig();
    const { entry, now } = await getOrCreateTodayLog(req.user.id, timezone);
    const local = localParts(now, timezone);

    if (!entry.checkInAt) throw BadRequest('Check in first before using lunch toggle');
    if (entry.checkOutAt) throw Conflict('You have already checked out for today');
    if (!entry.lunchStartedAt && local.hour < config.lunchStartHour) {
      throw BadRequest(`Lunch break opens at ${String(config.lunchStartHour).padStart(2, '0')}:00`);
    }
    if (entry.lunchStartedAt && !entry.lunchEndedAt && local.hour < config.lunchEndHour) {
      throw BadRequest(`Lunch break can be ended after ${String(config.lunchEndHour).padStart(2, '0')}:00`);
    }

    const data = entry.lunchStartedAt && !entry.lunchEndedAt
      ? { lunchEndedAt: now, lunchNote: req.body.note ? String(req.body.note).trim() : entry.lunchNote }
      : { lunchStartedAt: now, lunchNote: req.body.note ? String(req.body.note).trim() : null };

    const updated = await prisma.workdayLog.update({ where: { id: entry.id }, data });
    res.json({ ok: true, entry: serializeEntry(updated) });
  })
);

router.post(
  '/check-out',
  validate({ body: Joi.object({ report: Joi.string().min(1).max(10000).required(), timezone: Joi.string().allow('', null) }) }),
  asyncHandler(async (req, res) => {
    const timezone = normalizeTimezone(req.body.timezone);
    const config = await getAttendanceConfig();
    const wordCount = ensureMinimumWordsWithConfig(req.body.report, 'Logout report', config.minRequiredWords);
    const { entry, now } = await getOrCreateTodayLog(req.user.id, timezone);
    const local = localParts(now, timezone);

    if (!entry.checkInAt) throw BadRequest('Check in first before checking out');
    if (entry.checkOutAt) throw Conflict('You have already checked out for today');
    if (local.hour < config.checkOutHour) {
      throw BadRequest(`Logout report opens at ${String(config.checkOutHour).padStart(2, '0')}:00`);
    }

    const updated = await prisma.workdayLog.update({
      where: { id: entry.id },
      data: {
        timezone,
        lunchEndedAt: entry.lunchStartedAt && !entry.lunchEndedAt ? now : entry.lunchEndedAt,
        checkOutAt: now,
        checkOutReport: req.body.report.trim(),
        checkOutWordCount: wordCount,
      },
    });

    res.json({ ok: true, entry: serializeEntry(updated) });
  })
);

module.exports = router;
