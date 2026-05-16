'use strict';

const cron = require('node-cron');
const prisma = require('../database/prisma');
const logger = require('../utils/logger');
const notifications = require('../modules/notifications/notifications.service');

/**
 * Task automation engine.
 *
 * Two evaluation paths:
 *
 *   • Schedule-driven — `RECURRING_SCHEDULE` automations run on cron expressions
 *     pulled from `triggerData.cron`. We register one cron task per automation
 *     at boot and re-register when admins toggle them.
 *
 *   • Event-driven — `TASK_OVERDUE`, `TASK_CREATED`, etc. are evaluated either
 *     in a periodic sweep (every 5 minutes) for `TASK_OVERDUE`, or inline at
 *     the call site (other triggers — `runEventTriggered`).
 *
 * Actions are intentionally small and composable so the matrix of
 * trigger × action stays manageable.
 */

const scheduled = new Map(); // automationId → cron.ScheduledTask

async function runAction({ automation, context }) {
  const action = automation.action;
  const data = automation.actionData || {};
  try {
    switch (action) {
      case 'MOVE_TASK_STATUS': {
        if (!context.taskId) return;
        await prisma.task.update({ where: { id: context.taskId }, data: { status: data.status } });
        break;
      }
      case 'REASSIGN_TASK': {
        if (!context.taskId || !data.userId) return;
        await prisma.taskAssignee.deleteMany({ where: { taskId: context.taskId } });
        await prisma.taskAssignee.create({ data: { taskId: context.taskId, userId: data.userId } });
        break;
      }
      case 'NOTIFY_USER': {
        const userId = data.userId || context.userId;
        if (!userId) return;
        await notifications.notify({
          userId,
          kind: data.kind || 'TASK',
          title: data.title || `Automation: ${automation.name}`,
          body: data.body || '',
          data: { automationId: automation.id, ...context },
        });
        break;
      }
      case 'NOTIFY_MANAGER': {
        // Convention: managers are admins for now. Real impl would look up a
        // manager via a department/reporting model.
        const managers = await prisma.user.findMany({ where: { role: 'ADMIN', status: 'ACTIVE' } });
        await Promise.all(
          managers.map((m) =>
            notifications.notify({
              userId: m.id,
              kind: 'TASK',
              title: data.title || `Automation: ${automation.name}`,
              body: data.body || '',
              data: { automationId: automation.id, ...context },
            }).catch(() => {})
          )
        );
        break;
      }
      case 'CREATE_TASK': {
        await prisma.task.create({
          data: {
            title: data.title || 'Auto-generated task',
            description: data.description || null,
            status: data.status || 'TODO',
            priority: data.priority || 'MEDIUM',
            createdById: automation.createdById,
            channelId: data.channelId || null,
            spawnedByAutomationId: automation.id,
            recurrenceCron: automation.triggerData?.cron || null,
          },
        });
        break;
      }
      case 'POST_MESSAGE': {
        if (!data.channelId) return;
        await prisma.message.create({
          data: {
            channelId: data.channelId,
            authorId: data.authorId || automation.createdById,
            body: data.body || '',
            kind: 'SYSTEM',
          },
        });
        break;
      }
    }
    await prisma.automation.update({ where: { id: automation.id }, data: { lastRunAt: new Date() } });
  } catch (err) {
    logger.warn({ err: err.message, automationId: automation.id }, 'automation.action_failed');
  }
}

async function runEventTriggered({ trigger, context }) {
  const items = await prisma.automation.findMany({ where: { trigger, enabled: true } });
  for (const a of items) await runAction({ automation: a, context });
}

async function registerSchedules() {
  for (const t of scheduled.values()) t.stop();
  scheduled.clear();

  const items = await prisma.automation.findMany({ where: { trigger: 'RECURRING_SCHEDULE', enabled: true } });
  for (const a of items) {
    const expr = a.triggerData?.cron;
    if (!expr || !cron.validate(expr)) {
      logger.warn({ id: a.id, expr }, 'automation.schedule.invalid_cron');
      continue;
    }
    const task = cron.schedule(expr, () => runAction({ automation: a, context: {} }), { scheduled: true });
    scheduled.set(a.id, task);
  }
  logger.info({ count: scheduled.size }, 'automation.schedules_registered');
}

function startOverdueSweep() {
  // Every 5 minutes: find overdue tasks and run all TASK_OVERDUE automations.
  cron.schedule('*/5 * * * *', async () => {
    const overdueTasks = await prisma.task.findMany({
      where: {
        dueAt: { lt: new Date() },
        status: { notIn: ['DONE', 'CANCELLED'] },
      },
      select: { id: true, createdById: true, assignees: { select: { userId: true } } },
      take: 200,
    });
    for (const t of overdueTasks) {
      await runEventTriggered({
        trigger: 'TASK_OVERDUE',
        context: { taskId: t.id, ownerId: t.createdById, assigneeIds: t.assignees.map((a) => a.userId) },
      });
    }
  });
}

module.exports = { runAction, runEventTriggered, registerSchedules, startOverdueSweep };
