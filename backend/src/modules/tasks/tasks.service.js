'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden } = require('../../utils/errors');
const tenant = require('../../services/tenant');

const taskInclude = {
  createdBy: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
  assignees: { include: { user: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } } },
  completionReports: {
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
      recipients: {
        include: { user: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } },
        orderBy: { createdAt: 'asc' },
      },
    },
    orderBy: { createdAt: 'desc' },
  },
  subtasks: { orderBy: { order: 'asc' } },
  comments: {
    include: { author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } },
    orderBy: { createdAt: 'asc' },
  },
  attachments: true,
};

async function ensureVisible(task, user) {
  if (tenant.MULTI_TENANT) {
    tenant.assertSameTenant(user, task.tenantId);
  }
  if (['SUPER_ADMIN', 'ADMIN', 'MANAGER', 'PROJECT_COORDINATOR_MANAGER'].includes(user.role)) return;
  const assigned = task.assignees.some((a) => a.userId === user.id) || task.createdById === user.id;
  if (!assigned) throw Forbidden('Not allowed to access this task');
}

/** Flip SCHEDULED → TODO when delivery time has passed (cron backup). */
async function promoteDueScheduledTasks() {
  const now = new Date();
  const due = await prisma.task.findMany({
    where: { status: 'SCHEDULED', scheduledAt: { lte: now } },
    select: { id: true },
  });
  if (!due.length) return;
  await prisma.task.updateMany({
    where: { id: { in: due.map((t) => t.id) } },
    data: { status: 'TODO' },
  });
}

async function list({ user, status, assigneeId, q, page = 1, pageSize = 50, view = 'list' }) {
  await promoteDueScheduledTasks();
  const isAdmin = ['SUPER_ADMIN', 'ADMIN', 'MANAGER', 'PROJECT_COORDINATOR_MANAGER'].includes(user.role);
  const filters = [];
  if (status) filters.push({ status });
  if (assigneeId) filters.push({ assignees: { some: { userId: assigneeId } } });
  if (q) {
    filters.push({
      OR: [
        { title: { contains: q, mode: 'insensitive' } },
        { description: { contains: q, mode: 'insensitive' } },
      ],
    });
  }
  // Non-admins see only their tasks.
  if (!isAdmin) {
    filters.push({ OR: [{ createdById: user.id }, { assignees: { some: { userId: user.id } } }] });
  }
  // SCHEDULED tasks are hidden from assignees until the scheduler flips them.
  // The creator still sees them so they can edit or cancel before delivery.
  if (!status) {
    filters.push({
      NOT: {
        AND: [
          { status: 'SCHEDULED' },
          { createdById: { not: user.id } },
        ],
      },
    });
  }
  const where = tenant.tenantClause(user, filters.length ? { AND: filters } : {});

  if (view === 'kanban') {
    const items = await prisma.task.findMany({
      where,
      orderBy: [{ status: 'asc' }, { order: 'asc' }, { createdAt: 'desc' }],
      include: taskInclude,
    });
    const columns = { BACKLOG: [], TODO: [], IN_PROGRESS: [], REVIEW: [], DONE: [], CANCELLED: [], SCHEDULED: [] };
    for (const t of items) {
      if (!columns[t.status]) columns[t.status] = [];
      columns[t.status].push(t);
    }
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
  // Scheduled delivery: when scheduledAt is in the future, the task is
  // created as SCHEDULED so the assignee doesn't see it yet. A cron job
  // (jobs/index.js → scheduledTasksJob) promotes it to TODO + notifies
  // the assignee at the right moment.
  const scheduledAt = input.scheduledAt ? new Date(input.scheduledAt) : null;
  const isScheduledForLater = scheduledAt && scheduledAt > new Date();
  const status = isScheduledForLater
    ? 'SCHEDULED'
    : (input.status || 'TODO');
  const task = await prisma.task.create({
    data: {
      title: input.title,
      description: input.description || null,
      status,
      priority: input.priority || 'MEDIUM',
      dueAt: input.dueAt ? new Date(input.dueAt) : null,
      scheduledAt,
      createdById: creator.id,
      channelId: input.channelId || null,
      boardId: input.boardId || null,
      tenantId: tenant.userTenantId(creator),
      assignees: input.assigneeIds?.length
        ? { create: input.assigneeIds.map((uid) => ({ userId: uid })) }
        : undefined,
    },
    include: taskInclude,
  });
  return task;
}

async function update(id, input, user) {
  await getById(id, user);
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
  // Guard first so a caller who isn't an assignee (admin/creator, or a stale
  // client) gets a clean 403 instead of an opaque Prisma P2025 → 500.
  const existing = await prisma.taskAssignee.findUnique({
    where: { taskId_userId: { taskId, userId } },
    select: { id: true },
  });
  if (!existing) throw Forbidden('You are not assigned to this task');
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

  // Push the task to DONE once everyone who still owes work has finished.
  // DECLINED assignees count as "settled" — otherwise a task with one declined
  // assignee could never auto-complete and would draw overdue reminders
  // forever. We also require at least one COMPLETED so an all-declined task
  // isn't silently marked DONE.
  const pendingCount = await prisma.taskAssignee.count({
    where: { taskId, state: { notIn: ['COMPLETED', 'DECLINED'] } },
  });
  const completedCount = await prisma.taskAssignee.count({
    where: { taskId, state: 'COMPLETED' },
  });
  const allDone = pendingCount === 0 && completedCount > 0;
  if (allDone && t.status !== 'DONE') {
    await prisma.task.update({ where: { id: taskId }, data: { status: 'DONE' } });
  }
  const autoPromotedTask = await promoteNextTaskForUser({ userId, excludingTaskId: taskId });
  return { assignment: row, autoCompleted: allDone, autoPromotedTask };
}

const priorityWeight = { URGENT: 0, HIGH: 1, MEDIUM: 2, LOW: 3 };

async function promoteNextTaskForUser({ userId, excludingTaskId }) {
  const active = await prisma.task.count({
    where: {
      id: { not: excludingTaskId },
      status: { in: ['IN_PROGRESS', 'REVIEW'] },
      assignees: {
        some: {
          userId,
          state: { in: ['PENDING', 'ACCEPTED'] },
        },
      },
    },
  });
  if (active > 0) return null;

  const candidates = await prisma.task.findMany({
    where: {
      id: { not: excludingTaskId },
      status: 'TODO',
      assignees: {
        some: {
          userId,
          state: { in: ['PENDING', 'ACCEPTED'] },
        },
      },
    },
    include: taskInclude,
    take: 25,
    orderBy: [{ dueAt: 'asc' }, { order: 'asc' }, { createdAt: 'asc' }],
  });
  if (!candidates.length) return null;

  candidates.sort((a, b) => {
    const byPriority = (priorityWeight[a.priority] ?? 99) - (priorityWeight[b.priority] ?? 99);
    if (byPriority !== 0) return byPriority;
    const aDue = a.dueAt ? new Date(a.dueAt).getTime() : Number.MAX_SAFE_INTEGER;
    const bDue = b.dueAt ? new Date(b.dueAt).getTime() : Number.MAX_SAFE_INTEGER;
    if (aDue !== bDue) return aDue - bDue;
    return (a.order || 0) - (b.order || 0);
  });

  const next = candidates[0];
  await prisma.$transaction([
    prisma.task.update({
      where: { id: next.id },
      data: { status: 'IN_PROGRESS' },
    }),
    prisma.taskAssignee.updateMany({
      where: { taskId: next.id, userId, state: 'PENDING' },
      data: { state: 'ACCEPTED', acceptedAt: new Date() },
    }),
  ]);
  return prisma.task.findUnique({ where: { id: next.id }, include: taskInclude });
}

async function leaderboard({ user, limit = 20, sinceDays = 30 }) {
  const since = new Date(Date.now() - sinceDays * 86_400_000);
  const grouped = await prisma.taskAssignee.groupBy({
    by: ['userId'],
    where: {
      state: 'COMPLETED',
      completedAt: { gte: since },
      ...(tenant.MULTI_TENANT
        ? { task: { tenantId: tenant.userTenantId(user) } }
        : {}),
    },
    _avg: { score: true },
    _count: { _all: true },
    _max: { completedAt: true },
    orderBy: { _avg: { score: 'desc' } },
    take: limit,
  });
  if (grouped.length === 0) return { items: [] };
  const userIds = grouped.map((g) => g.userId);
  const users = await prisma.user.findMany({
    where: tenant.tenantClause(user, { id: { in: userIds } }),
    select: { id: true, name: true, userId: true, avatarUrl: true, role: true, isClient: true, departmentId: true },
  });
  const byId = Object.fromEntries(users.map((u) => [u.id, u]));

  // Per-user on-time rate + streak — cheap N+1 since N ≤ limit (≤20 by default).
  const items = (await Promise.all(grouped.map(async (g) => {
    const u = byId[g.userId];
    if (!u) return null;
    const summary = await scoring.userSummary(prisma, g.userId);
    return {
      user: u,
      avgScore: Math.round(g._avg.score ?? 0),
      completed: g._count._all,
      lastCompletedAt: g._max.completedAt,
      onTimeRate: summary.onTimeRate,
      streak: summary.streak,
    };
  }))).filter(Boolean);

  return { items, sinceDays };
}

module.exports = {
  list, getById, create, update, move, remove,
  addComment, addSubtask, toggleSubtask,
  accept, decline, complete, leaderboard, promoteNextTaskForUser,
};
