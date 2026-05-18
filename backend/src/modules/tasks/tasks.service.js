'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden } = require('../../utils/errors');

const taskInclude = {
  assignees: { include: { user: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } } },
  subtasks: { orderBy: { order: 'asc' } },
  comments: {
    include: { author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } },
    orderBy: { createdAt: 'asc' },
  },
  attachments: true,
};

async function ensureVisible(task, user) {
  if (['SUPER_ADMIN', 'ADMIN'].includes(user.role)) return;
  const assigned = task.assignees.some((a) => a.userId === user.id) || task.createdById === user.id;
  if (!assigned) throw Forbidden('Not allowed to access this task');
}

async function list({ user, status, assigneeId, q, page = 1, pageSize = 50, view = 'list' }) {
  const where = {
    ...(status ? { status } : {}),
    ...(assigneeId ? { assignees: { some: { userId: assigneeId } } } : {}),
    ...(q
      ? {
          OR: [
            { title: { contains: q, mode: 'insensitive' } },
            { description: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
    // Non-admins see only their tasks
    ...(!['SUPER_ADMIN', 'ADMIN'].includes(user.role)
      ? { OR: [{ createdById: user.id }, { assignees: { some: { userId: user.id } } }] }
      : {}),
  };

  if (view === 'kanban') {
    const items = await prisma.task.findMany({
      where,
      orderBy: [{ status: 'asc' }, { order: 'asc' }, { createdAt: 'desc' }],
      include: taskInclude,
    });
    const columns = { BACKLOG: [], TODO: [], IN_PROGRESS: [], REVIEW: [], DONE: [], CANCELLED: [] };
    for (const t of items) columns[t.status].push(t);
    return { view, columns };
  }

  const [total, items] = await prisma.$transaction([
    prisma.task.count({ where }),
    prisma.task.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: taskInclude,
    }),
  ]);
  return { total, page, pageSize, items };
}

async function getById(id, user) {
  const task = await prisma.task.findUnique({ where: { id }, include: taskInclude });
  if (!task) throw NotFound('Task not found');
  await ensureVisible(task, user);
  return task;
}

async function create(input, creator) {
  const task = await prisma.task.create({
    data: {
      title: input.title,
      description: input.description || null,
      status: input.status || 'TODO',
      priority: input.priority || 'MEDIUM',
      dueAt: input.dueAt ? new Date(input.dueAt) : null,
      createdById: creator.id,
      channelId: input.channelId || null,
      boardId: input.boardId || null,
      assignees: input.assigneeIds?.length
        ? { create: input.assigneeIds.map((uid) => ({ userId: uid })) }
        : undefined,
    },
    include: taskInclude,
  });
  return task;
}

async function update(id, input, user) {
  const existing = await getById(id, user);
  const data = { ...input };
  delete data.assigneeIds;
  if (data.dueAt) data.dueAt = new Date(data.dueAt);

  const updated = await prisma.$transaction(async (tx) => {
    const t = await tx.task.update({ where: { id }, data });
    if (input.assigneeIds) {
      await tx.taskAssignee.deleteMany({ where: { taskId: id } });
      if (input.assigneeIds.length) {
        await tx.taskAssignee.createMany({
          data: input.assigneeIds.map((uid) => ({ taskId: id, userId: uid })),
        });
      }
    }
    return tx.task.findUnique({ where: { id: t.id }, include: taskInclude });
  });

  return updated;
}

async function move({ id, status, order }, user) {
  await getById(id, user);
  return prisma.task.update({
    where: { id },
    data: { status, order: typeof order === 'number' ? order : 0 },
    include: taskInclude,
  });
}

async function remove(id, user) {
  if (!['SUPER_ADMIN', 'ADMIN'].includes(user.role)) {
    const t = await prisma.task.findUnique({ where: { id } });
    if (!t || t.createdById !== user.id) throw Forbidden();
  }
  await prisma.task.delete({ where: { id } }).catch(() => {});
}

async function addComment({ taskId, user, body }) {
  await getById(taskId, user);
  return prisma.taskComment.create({
    data: { taskId, authorId: user.id, body },
    include: { author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } },
  });
}

async function addSubtask({ taskId, title }) {
  const count = await prisma.subtask.count({ where: { taskId } });
  return prisma.subtask.create({ data: { taskId, title, order: count } });
}

async function toggleSubtask({ id, done }) {
  return prisma.subtask.update({ where: { id }, data: { done } });
}

// ---------------------------------------------------------------------------
// Assignment lifecycle: PENDING → ACCEPTED → COMPLETED  (or DECLINED)
// ---------------------------------------------------------------------------

const scoring = require('../../services/scoring');

/** Generic transition helper. Returns the updated row (with task + user). */
async function _transition({ taskId, userId, state, data = {} }) {
  return prisma.taskAssignee.update({
    where: { taskId_userId: { taskId, userId } },
    data: { state, ...data },
    include: {
      task: { select: { id: true, title: true, dueAt: true, priority: true, createdById: true, status: true } },
      user: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
    },
  });
}

async function accept({ taskId, userId }) {
  return _transition({ taskId, userId, state: 'ACCEPTED', data: { acceptedAt: new Date() } });
}

async function decline({ taskId, userId }) {
  return _transition({ taskId, userId, state: 'DECLINED', data: { declinedAt: new Date() } });
}

async function complete({ taskId, userId }) {
  // Pull the task to score on its priority + dueAt.
  const t = await prisma.task.findUnique({ where: { id: taskId } });
  if (!t) throw NotFound('Task not found');

  const completedAt = new Date();
  const { score, reason } = scoring.compute({ dueAt: t.dueAt, completedAt, priority: t.priority });

  const row = await _transition({
    taskId, userId,
    state: 'COMPLETED',
    data: { completedAt, score, scoreReason: reason },
  });

  // If every assignee has marked complete, push the task into DONE so the
  // creator's kanban reflects it without manual intervention.
  const remaining = await prisma.taskAssignee.count({
    where: { taskId, NOT: { state: 'COMPLETED' } },
  });
  if (remaining === 0 && t.status !== 'DONE') {
    await prisma.task.update({ where: { id: taskId }, data: { status: 'DONE' } });
  }
  return { assignment: row, autoCompleted: remaining === 0 };
}

async function leaderboard({ limit = 20, sinceDays = 30 }) {
  const since = new Date(Date.now() - sinceDays * 86_400_000);
  const grouped = await prisma.taskAssignee.groupBy({
    by: ['userId'],
    where: { state: 'COMPLETED', completedAt: { gte: since } },
    _avg: { score: true },
    _count: { _all: true },
    _max: { completedAt: true },
    orderBy: { _avg: { score: 'desc' } },
    take: limit,
  });
  if (grouped.length === 0) return { items: [] };
  const userIds = grouped.map((g) => g.userId);
  const users = await prisma.user.findMany({
    where: { id: { in: userIds } },
    select: { id: true, name: true, userId: true, avatarUrl: true, role: true, isClient: true, departmentId: true },
  });
  const byId = Object.fromEntries(users.map((u) => [u.id, u]));

  // Per-user on-time rate + streak — cheap N+1 since N ≤ limit (≤20 by default).
  const items = await Promise.all(grouped.map(async (g) => {
    const summary = await scoring.userSummary(prisma, g.userId);
    return {
      user: byId[g.userId],
      avgScore: Math.round(g._avg.score ?? 0),
      completed: g._count._all,
      lastCompletedAt: g._max.completedAt,
      onTimeRate: summary.onTimeRate,
      streak: summary.streak,
    };
  }));

  return { items, sinceDays };
}

module.exports = {
  list, getById, create, update, move, remove,
  addComment, addSubtask, toggleSubtask,
  accept, decline, complete, leaderboard,
};
