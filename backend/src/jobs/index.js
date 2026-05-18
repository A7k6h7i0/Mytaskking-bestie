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

// Every 5 minutes — find tasks whose dueAt is in the next 15 minutes and
// haven't been reminded yet, then ping all their assignees. We track
// "reminded" by overloading the task's `recurrenceCron` column as a marker
// (cheap; no schema change). A proper system would have its own table.
function dueReminderJob() {
  cron.schedule('*/5 * * * *', async () => {
    const now = new Date();
    const horizon = new Date(now.getTime() + 15 * 60_000);
    const due = await prisma.task.findMany({
      where: {
        dueAt: { gte: now, lte: horizon },
        status: { notIn: ['DONE', 'CANCELLED'] },
      },
      include: { assignees: { select: { userId: true } } },
    });
    for (const t of due) {
      // De-dupe: write a marker on the row so we don't spam every 5 minutes.
      const markerKey = `reminded:${Math.floor(t.dueAt.getTime() / 60_000)}`;
      if (t.recurrenceCron === markerKey) continue;
      await prisma.task.update({ where: { id: t.id }, data: { recurrenceCron: markerKey } }).catch(() => {});
      for (const a of t.assignees) {
        await notifications.notify({
          userId: a.userId,
          kind: 'TASK',
          title: 'Due soon',
          body: `${t.title} — due ${new Date(t.dueAt).toUTCString()}`,
          data: { taskId: t.id, reminder: true },
        }).catch(() => {});
      }
    }
    if (due.length) logger.info({ count: due.length }, 'jobs.task_reminders.fired');
  });
}

module.exports = function startJobs() {
  expireClientsJob();
  followupRemindersJob();
  dueReminderJob();
  automations.startOverdueSweep();
  automations.registerSchedules().catch((err) => logger.warn({ err: err.message }, 'jobs.automations.register_failed'));
  logger.info('jobs.started');
};
