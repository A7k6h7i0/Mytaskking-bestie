'use strict';

const cron = require('node-cron');
const prisma = require('../database/prisma');
const logger = require('../utils/logger');
const notifications = require('../modules/notifications/notifications.service');
const automations = require('../services/automations');

// Every 15 minutes — expire clients whose access window has elapsed.
function expireClientsJob() {
  cron.schedule('*/15 * * * *', async () => {
    const result = await prisma.user.updateMany({
      where: {
        isClient: true,
        status: 'ACTIVE',
        accessEndsAt: { lt: new Date() },
      },
      data: { status: 'EXPIRED' },
    });
    if (result.count) logger.info({ count: result.count }, 'jobs.clients.expired');
  });
}

// Every morning at 9 — push followup reminders to telecallers.
function followupRemindersJob() {
  cron.schedule('0 9 * * *', async () => {
    const start = new Date(); start.setHours(0, 0, 0, 0);
    const end = new Date(); end.setHours(23, 59, 59, 999);
    const leads = await prisma.lead.findMany({
      where: { nextFollowAt: { gte: start, lte: end }, ownerId: { not: null } },
    });
    for (const lead of leads) {
      await notifications.notify({
        userId: lead.ownerId,
        kind: 'LEAD_FOLLOWUP',
        title: 'Followup due today',
        body: `${lead.name} — ${lead.phone}`,
        data: { leadId: lead.id },
      }).catch((err) => logger.warn({ err: err.message }, 'jobs.followup.notify_failed'));
    }
    if (leads.length) logger.info({ count: leads.length }, 'jobs.followups.notified');
  });
}

// ---------------------------------------------------------------------------
// Task deadline reminder pipeline — four phases:
//
//   T-15m: "Due in 15 minutes"
//   T-5m:  "Due in 5 minutes"
//   T+0:   "Time's up"
//   T+30m, T+60m, T+90m, …: recurring "Still overdue" until DONE/CANCELLED.
//
// All four phases share one cron tick (every minute) for tight scheduling.
// De-dup markers live on the existing `recurrenceCron` text column so we
// don't spam — each phase writes a different marker key.
// ---------------------------------------------------------------------------

const REMINDER_PHASES = [
  { id: 'pre15', label: '15 minutes left', minutesBefore: 15, withinSeconds: 90 },
  { id: 'pre5',  label: '5 minutes left',  minutesBefore: 5,  withinSeconds: 90 },
  { id: 'due',   label: 'Time\'s up',      minutesBefore: 0,  withinSeconds: 90 },
];

function _markerFor(taskId, phaseId, dueMs, recurrenceMin = 0) {
  // Keep markers short — the column is a string. Recurrence min lets us
  // collapse e.g. "+30", "+60" into the same column without bumping schema.
  const dueBucket = Math.floor(dueMs / 60_000);
  return `R:${phaseId}:${dueBucket}${recurrenceMin ? ':' + recurrenceMin : ''}`;
}

async function _hasMarker(taskId, marker) {
  const row = await prisma.task.findUnique({ where: { id: taskId }, select: { recurrenceCron: true } });
  if (!row) return true;
  // Multiple markers may need to coexist. Store as comma-separated.
  const current = (row.recurrenceCron || '').split(',').map((s) => s.trim()).filter(Boolean);
  return current.includes(marker);
}

async function _addMarker(taskId, marker) {
  const row = await prisma.task.findUnique({ where: { id: taskId }, select: { recurrenceCron: true } });
  if (!row) return;
  const current = (row.recurrenceCron || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (current.includes(marker)) return;
  current.push(marker);
  // Cap at 12 markers (≈ 6 hours of overdue + pre-warnings) so we don't
  // grow this string unboundedly.
  while (current.length > 12) current.shift();
  await prisma.task.update({
    where: { id: taskId },
    data: { recurrenceCron: current.join(',') },
  }).catch(() => {});
}

// Only people who still owe work on the task — drops anyone who has already
// COMPLETED or DECLINED their assignment so finished users stop getting
// "due / overdue" reminders.
function _pendingAssignees(assignees) {
  return (assignees || []).filter(
    (a) => a.state !== 'COMPLETED' && a.state !== 'DECLINED'
  );
}

async function _notifyAll(task, assignees, { title, body, data }) {
  const io = global.io || null;
  for (const a of assignees) {
    await notifications.notify({
      userId: a.userId,
      kind: 'TASK',
      title,
      body,
      data: { taskId: task.id, ...data },
      io,
    }).catch(() => {});
  }
}

function taskRemindersJob() {
  // Every minute keeps the warning windows tight (a 5-min warning would
  // otherwise drift by up to the cron interval).
  cron.schedule('* * * * *', async () => {
    const now = new Date();
    const nowMs = now.getTime();

    // Pre-due windows — fetch tasks coming due in the next 16 minutes.
    const horizon = new Date(nowMs + 16 * 60_000);
    const upcoming = await prisma.task.findMany({
      where: {
        dueAt: { gte: new Date(nowMs - 60_000), lte: horizon },
        status: { notIn: ['DONE', 'CANCELLED'] },
      },
      include: { assignees: { select: { userId: true, state: true } } },
    });

    for (const t of upcoming) {
      const dueMs = new Date(t.dueAt).getTime();
      const deltaSec = (dueMs - nowMs) / 1000;
      for (const phase of REMINDER_PHASES) {
        const target = phase.minutesBefore * 60;
        if (Math.abs(deltaSec - target) > phase.withinSeconds) continue;
        const marker = _markerFor(t.id, phase.id, dueMs);
        if (await _hasMarker(t.id, marker)) continue;
        await _addMarker(t.id, marker);
        const title = phase.id === 'due' ? `Time's up — ${t.title}` : `Due ${phase.label} — ${t.title}`;
        const body = phase.id === 'due'
          ? 'Your task deadline just hit. Mark it complete or extend the due date.'
          : `Deadline ${new Date(dueMs).toUTCString()}`;
        // Don't nag people who already finished (or declined) their part.
        const pending = _pendingAssignees(t.assignees);
        if (pending.length === 0) continue;
        await _notifyAll(t, pending, {
          title,
          body,
          data: { reminder: phase.id, dueAt: new Date(dueMs).toISOString() },
        });
      }
    }
    if (upcoming.length) logger.info({ count: upcoming.length }, 'jobs.task_reminders.window_scanned');
  });
}

// Every 30 minutes — for tasks already past their deadline, send a recurring
// "still overdue" push. Stops automatically when the task moves to DONE /
// CANCELLED. Distinct markers per 30-min slot so we never double-fire.
function overdueReminderJob() {
  cron.schedule('*/30 * * * *', async () => {
    const now = new Date();
    const nowMs = now.getTime();
    const overdue = await prisma.task.findMany({
      where: {
        dueAt: { lt: now },
        status: { notIn: ['DONE', 'CANCELLED'] },
      },
      include: { assignees: { select: { userId: true, state: true } } },
    });
    for (const t of overdue) {
      const dueMs = new Date(t.dueAt).getTime();
      const overdueMin = Math.floor((nowMs - dueMs) / 60_000);
      // Round to nearest 30-min slot so the marker key is stable.
      const slot = Math.floor(overdueMin / 30) * 30;
      // Skip the 0-min slot (the at-deadline ping is handled by taskRemindersJob).
      if (slot < 30) continue;
      const marker = _markerFor(t.id, 'over', dueMs, slot);
      if (await _hasMarker(t.id, marker)) continue;
      await _addMarker(t.id, marker);
      const hours = Math.floor(overdueMin / 60);
      const mins = overdueMin % 60;
      const elapsed = hours > 0
        ? `${hours}h ${mins}m`
        : `${mins}m`;
      const pending = _pendingAssignees(t.assignees);
      if (pending.length === 0) continue;
      await _notifyAll(t, pending, {
        title: `Still overdue — ${t.title}`,
        body: `${elapsed} past deadline. Mark complete or push the due date.`,
        data: { reminder: 'overdue', overdueMinutes: overdueMin },
      });
    }
    if (overdue.length) logger.info({ count: overdue.length }, 'jobs.task_overdue.scanned');
  });
}

// Promotes any SCHEDULED tasks whose `scheduledAt` has just passed into
// TODO and notifies every assignee — the heart of the "schedule a task for
// someone, they get it at delivery time" feature.
function scheduledTasksJob() {
  cron.schedule('* * * * *', async () => {
    const now = new Date();
    const due = await prisma.task.findMany({
      where: { status: 'SCHEDULED', scheduledAt: { lte: now } },
      include: {
        assignees: { include: { user: { select: { id: true, name: true } } } },
        createdBy: { select: { id: true, name: true } },
      },
    });
    if (!due.length) return;
    for (const t of due) {
      try {
        await prisma.task.update({
          where: { id: t.id },
          data: { status: 'TODO' },
        });
        const io = global.io || null;
        for (const a of t.assignees) {
          io?.to(`user:${a.userId}`).emit('task.assigned', {
            task: t,
            assignerName: t.createdBy?.name || 'Someone',
          });
        }
        await _notifyAll(
          t,
          t.assignees.map((a) => ({ userId: a.userId })),
          {
            title: `Scheduled task — ${t.title}`,
            body: t.description
              ? t.description.slice(0, 140)
              : `From ${t.createdBy?.name || 'a teammate'}`,
            data: {
              taskId: t.id,
              kind: 'TASK',
              from: t.createdBy?.name || '',
            },
          },
        );
      } catch (err) {
        logger.warn({ err: err.message, taskId: t.id },
            'jobs.scheduled_tasks.promote_failed');
      }
    }
    logger.info({ count: due.length }, 'jobs.scheduled_tasks.released');
  });
}

module.exports = function startJobs() {
  expireClientsJob();
  followupRemindersJob();
  taskRemindersJob();
  overdueReminderJob();
  scheduledTasksJob();
  automations.startOverdueSweep();
  automations.registerSchedules().catch((err) => logger.warn({ err: err.message }, 'jobs.automations.register_failed'));
  logger.info('jobs.started');
};
