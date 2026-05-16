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

module.exports = function startJobs() {
  expireClientsJob();
  followupRemindersJob();
  automations.startOverdueSweep();
  automations.registerSchedules().catch((err) => logger.warn({ err: err.message }, 'jobs.automations.register_failed'));
  logger.info('jobs.started');
};
