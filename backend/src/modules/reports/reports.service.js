'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const notifications = require('../notifications/notifications.service');

const personSelect = { id: true, userId: true, name: true, avatarUrl: true, role: true, isClient: true };

const reportInclude = {
  task: { select: { id: true, title: true, status: true, priority: true, dueAt: true } },
  author: { select: personSelect },
  recipients: {
    include: { user: { select: personSelect } },
    orderBy: { createdAt: 'asc' },
  },
};

function wordCount(body) {
  return String(body || '').trim().split(/\s+/).filter(Boolean).length;
}

function assertReportBody(body) {
  const count = wordCount(body);
  if (count < 1) throw BadRequest('Report is required');
  if (count > 120) throw BadRequest('Report must be 120 words or less');
  return count;
}

function uniqueIds(ids) {
  return Array.from(new Set((ids || []).map((id) => String(id || '').trim()).filter(Boolean)));
}

async function ensureRecipients(recipientIds) {
  const ids = uniqueIds(recipientIds);
  if (!ids.length) throw BadRequest('Select at least one person to report to');
  const users = await prisma.user.findMany({
    where: { id: { in: ids }, status: 'ACTIVE' },
    select: { id: true },
  });
  const existing = new Set(users.map((u) => u.id));
  const missing = ids.filter((id) => !existing.has(id));
  if (missing.length) throw BadRequest('One or more report recipients are invalid');
  return ids;
}

async function validateReportInput(body, recipientIds) {
  assertReportBody(body);
  return ensureRecipients(recipientIds);
}

async function findVisibleReport(id, user) {
  const report = await prisma.taskCompletionReport.findUnique({
    where: { id },
    include: reportInclude,
  });
  if (!report) throw NotFound('Report not found');
  const isAuthor = report.authorId === user.id;
  const isRecipient = report.recipients.some((recipient) => recipient.userId === user.id);
  const isAdmin = ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
  if (!isAuthor && !isRecipient && !isAdmin) throw Forbidden('Not allowed to view this report');
  return report;
}

async function listForUser(user) {
  const [mine, received] = await prisma.$transaction([
    prisma.taskCompletionReport.findMany({
      where: { authorId: user.id },
      include: reportInclude,
      orderBy: { createdAt: 'desc' },
      take: 100,
    }),
    prisma.taskCompletionReport.findMany({
      where: { recipients: { some: { userId: user.id } } },
      include: reportInclude,
      orderBy: { createdAt: 'desc' },
      take: 100,
    }),
  ]);
  return { mine, received };
}

async function syncRecipients(tx, reportId, recipientIds) {
  const ids = uniqueIds(recipientIds);
  await tx.taskReportRecipient.deleteMany({
    where: {
      reportId,
      userId: { notIn: ids },
    },
  });
  await Promise.all(
    ids.map((userId) =>
      tx.taskReportRecipient.upsert({
        where: { reportId_userId: { reportId, userId } },
        update: {},
        create: { reportId, userId },
      })
    )
  );
  return ids;
}

async function notifyRecipients({ report, recipientIds, actor, io }) {
  await Promise.all(
    recipientIds
      .filter((userId) => userId !== actor.id)
      .map((userId) =>
        notifications.notify({
          userId,
          kind: 'TASK',
          title: `${actor.name} reported task completion`,
          body: report.task?.title || 'Task completed',
          data: { reportId: report.id, taskId: report.taskId },
          io,
        }).catch(() => {})
      )
  );
}

async function createForCompletion({ taskId, author, assignmentId, body, recipientIds, io }) {
  const count = assertReportBody(body);
  const ids = await ensureRecipients(recipientIds);

  const report = await prisma.$transaction(async (tx) => {
    const existing = assignmentId
      ? await tx.taskCompletionReport.findUnique({ where: { assignmentId } })
      : null;
    const row = existing
      ? await tx.taskCompletionReport.update({
          where: { id: existing.id },
          data: { body: body.trim(), wordCount: count },
        })
      : await tx.taskCompletionReport.create({
          data: {
            taskId,
            authorId: author.id,
            assignmentId,
            body: body.trim(),
            wordCount: count,
          },
        });
    await syncRecipients(tx, row.id, ids);
    return tx.taskCompletionReport.findUnique({ where: { id: row.id }, include: reportInclude });
  });

  await notifyRecipients({ report, recipientIds: ids, actor: author, io });
  io?.emit('task.report.created', { report });
  return report;
}

async function updateReport({ id, user, body, recipientIds, io }) {
  const existing = await findVisibleReport(id, user);
  if (existing.authorId !== user.id && !['SUPER_ADMIN', 'ADMIN'].includes(user.role)) {
    throw Forbidden('Only the report author can edit this report');
  }
  const count = assertReportBody(body);
  const before = new Set(existing.recipients.map((recipient) => recipient.userId));
  const ids = await ensureRecipients(recipientIds);

  const report = await prisma.$transaction(async (tx) => {
    await tx.taskCompletionReport.update({
      where: { id },
      data: { body: body.trim(), wordCount: count },
    });
    await syncRecipients(tx, id, ids);
    return tx.taskCompletionReport.findUnique({ where: { id }, include: reportInclude });
  });

  const newRecipientIds = ids.filter((recipientId) => !before.has(recipientId));
  if (newRecipientIds.length) {
    await notifyRecipients({ report, recipientIds: newRecipientIds, actor: user, io });
  }
  io?.emit('task.report.updated', { report });
  return report;
}

async function respond({ id, user, body, io }) {
  const text = String(body || '').trim();
  if (!text) throw BadRequest('Response is required');
  if (wordCount(text) > 120) throw BadRequest('Response must be 120 words or less');

  const existing = await findVisibleReport(id, user);
  const recipient = existing.recipients.find((row) => row.userId === user.id);
  if (!recipient) throw Forbidden('Only selected report recipients can respond');
  const now = new Date();

  await prisma.taskReportRecipient.update({
    where: { reportId_userId: { reportId: id, userId: user.id } },
    data: {
      responseBody: text,
      respondedAt: recipient.respondedAt || now,
      responseUpdatedAt: now,
    },
  });
  const report = await prisma.taskCompletionReport.findUnique({ where: { id }, include: reportInclude });

  if (report.authorId !== user.id) {
    notifications.notify({
      userId: report.authorId,
      kind: 'TASK',
      title: `${user.name} responded to your report`,
      body: report.task?.title || text,
      data: { reportId: id, taskId: report.taskId },
      io,
    }).catch(() => {});
  }
  io?.emit('task.report.response', { reportId: id, userId: user.id, report });
  return report;
}

module.exports = {
  listForUser,
  createForCompletion,
  updateReport,
  respond,
  wordCount,
  assertReportBody,
  validateReportInput,
};
