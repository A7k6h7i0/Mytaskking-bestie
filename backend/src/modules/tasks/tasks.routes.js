'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./tasks.service');
const audit = require('../../services/audit');
const automations = require('../../services/automations');
const notifications = require('../notifications/notifications.service');
const prisma = require('../../database/prisma');

const router = Router();
router.use(requireAuth);

const Status = Joi.string().valid('BACKLOG', 'TODO', 'IN_PROGRESS', 'REVIEW', 'DONE', 'CANCELLED');
const Priority = Joi.string().valid('LOW', 'MEDIUM', 'HIGH', 'URGENT');

/**
 * Sends the two-sided assignment notifications:
 *   • each assignee gets "<assigner> assigned you '<title>' — due <when>"
 *   • the assigner gets a confirmation receipt with the same context
 *
 * Also pushes a `task.assigned` socket event to each assignee's user room so
 * a live toast pops without waiting for the notification feed to refetch.
 * Notifications are fire-and-forget; the API response doesn't wait.
 */
async function fanOutAssignment({ task, assigneeIds, assigner, io, isUpdate = false }) {
  if (!assigneeIds || assigneeIds.length === 0) return;
  const due = task.dueAt ? new Date(task.dueAt).toUTCString() : null;
  const verb = isUpdate ? 'updated the assignment of' : 'assigned you';
  const uniqueAssigneeIds = Array.from(new Set(assigneeIds));
  const supervisorLinks = await prisma.userSupervisor.findMany({
    where: { userId: { in: uniqueAssigneeIds } },
    include: {
      user: { select: { id: true, name: true, customTitle: true, role: true } },
      supervisor: { select: { id: true, name: true, customTitle: true, role: true } },
    },
  });
  const supervisorRecipients = new Map();
  for (const link of supervisorLinks) {
    if (!link.supervisor || link.supervisorId === assigner.id) continue;
    const existing = supervisorRecipients.get(link.supervisorId) || { person: link.supervisor, assignees: [] };
    existing.assignees.push(link.user);
    supervisorRecipients.set(link.supervisorId, existing);
  }

  await Promise.all([
    // ----- assignees -----
    ...uniqueAssigneeIds
      .filter((id) => id !== assigner.id) // don't ping yourself if you self-assigned
      .map((userId) =>
        notifications.notify({
          userId,
          kind: 'TASK',
          title: `${assigner.name} ${verb} a task`,
          body: due ? `${task.title} — due ${due}` : task.title,
          data: {
            taskId: task.id,
            assignerId: assigner.id,
            dueAt: task.dueAt || null,
            priority: task.priority,
          },
        }).catch(() => {})
      ),

    // ----- assigner (self-confirmation) -----
    notifications.notify({
      userId: assigner.id,
      kind: 'TASK',
      title: `Assigned · ${task.title}`,
      body: `To ${uniqueAssigneeIds.length} ${uniqueAssigneeIds.length === 1 ? 'person' : 'people'}${due ? ` · due ${due}` : ''}`,
      data: { taskId: task.id, assigneeIds: uniqueAssigneeIds, dueAt: task.dueAt || null },
    }).catch(() => {}),

    ...Array.from(supervisorRecipients.values()).map(({ person, assignees }) =>
      notifications.notify({
        userId: person.id,
        kind: 'TASK',
        title: `${assigner.name} assigned work to your team`,
        body: `${task.title} · ${assignees.map((entry) => entry.name).join(', ')}${due ? ` · due ${due}` : ''}`,
        data: {
          taskId: task.id,
          assignerId: assigner.id,
          assigneeIds: assignees.map((entry) => entry.id),
          supervisorId: person.id,
        },
      }).catch(() => {})
    ),
  ]);

  // Realtime toast to each assignee's user room.
  for (const userId of uniqueAssigneeIds) {
    io?.to(`user:${userId}`).emit('task.assigned', {
      task,
      assignerId: assigner.id,
      assignerName: assigner.name,
    });
  }
  for (const [userId] of supervisorRecipients) {
    io?.to(`user:${userId}`).emit('task.supervisor_assigned', {
      task,
      assignerId: assigner.id,
      assignerName: assigner.name,
    });
  }
}

router.get(
  '/',
  validate({
    query: Joi.object({
      view: Joi.string().valid('list', 'kanban', 'calendar').default('list'),
      status: Status,
      assigneeId: Joi.string(),
      q: Joi.string().allow(''),
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(200).default(50),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.list({ user: req.user, ...req.query })))
);

// ⚠️ Keep `/leaderboard` ABOVE `/:id` — Express matches in order, and
// `/leaderboard` would otherwise resolve as `getById('leaderboard')`.
router.get(
  '/leaderboard',
  validate({
    query: Joi.object({
      limit: Joi.number().integer().min(1).max(100).default(20),
      sinceDays: Joi.number().integer().min(1).max(365).default(30),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.leaderboard(req.query)))
);

router.get('/:id', asyncHandler(async (req, res) => res.json(await service.getById(req.params.id, req.user))));

/**
 * Anyone authenticated can create a task and assign it to anyone. The legacy
 * RBAC default already covers `task.create` for every role and the API does
 * not gate `assigneeIds` against the caller's role — by design, so a peer-
 * to-peer "ask Priya to do X" flow works without admin intervention.
 *
 * Clients are intentionally excluded — they can read tasks they're added to
 * but can't create or assign. The service-layer permission check enforces
 * that downstream.
 */
router.post(
  '/',
  validate({
    body: Joi.object({
      title: Joi.string().min(1).max(240).required(),
      description: Joi.string().max(8000).allow('', null),
      status: Status,
      priority: Priority,
      dueAt: Joi.date().iso(),
      scheduledAt: Joi.date().iso().allow(null),
      assigneeIds: Joi.array().items(Joi.string()),
      channelId: Joi.string().allow(null, ''),
      boardId: Joi.string().allow(null, ''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const task = await service.create(req.body, req.user);
    audit.record({ kind: 'task.created', entity: 'task', entityId: task.id, payload: { title: task.title, status: task.status }, req });
    if (req.body.assigneeIds?.length) {
      audit.record({ kind: 'task.assigned', entity: 'task', entityId: task.id, payload: { assigneeIds: req.body.assigneeIds }, req });
    }
    automations.runEventTriggered({ trigger: 'TASK_CREATED', context: { taskId: task.id, ownerId: req.user.id } })
      .catch(() => {});
    req.app.get('io')?.emit('task.created', task);

    // For SCHEDULED tasks we *don't* fan out the assignment now — the
    // cron job (scheduledTasksJob) will fire `task.assigned` + push the
    // moment scheduledAt passes. The creator still gets confirmation via
    // the 201 response.
    if (task.status !== 'SCHEDULED') {
      fanOutAssignment({
        task,
        assigneeIds: req.body.assigneeIds || [],
        assigner: req.user,
        io: req.app.get('io'),
      }).catch(() => {});
    }

    res.status(201).json(task);
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      title: Joi.string().min(1).max(240),
      description: Joi.string().max(8000).allow('', null),
      status: Status,
      priority: Priority,
      dueAt: Joi.date().iso().allow(null),
      assigneeIds: Joi.array().items(Joi.string()),
      order: Joi.number().integer(),
    }),
  }),
  asyncHandler(async (req, res) => {
    // Capture pre-update assignees so we can diff and only notify the newly-added ones.
    const before = req.body.assigneeIds
      ? await prisma.taskAssignee.findMany({ where: { taskId: req.params.id }, select: { userId: true } })
      : [];
    const beforeIds = new Set(before.map((a) => a.userId));

    const task = await service.update(req.params.id, req.body, req.user);

    if (req.body.assigneeIds) {
      const newlyAdded = req.body.assigneeIds.filter((id) => !beforeIds.has(id));
      if (newlyAdded.length) {
        audit.record({ kind: 'task.assigned', entity: 'task', entityId: task.id, payload: { assigneeIds: newlyAdded }, req });
        fanOutAssignment({
          task,
          assigneeIds: newlyAdded,
          assigner: req.user,
          io: req.app.get('io'),
          isUpdate: true,
        }).catch(() => {});
      }
    }

    req.app.get('io')?.emit('task.updated', task);
    res.json(task);
  })
);

router.post(
  '/:id/move',
  validate({ body: Joi.object({ status: Status.required(), order: Joi.number().integer() }) }),
  asyncHandler(async (req, res) => {
    const task = await service.move({ id: req.params.id, ...req.body }, req.user);
    audit.record({ kind: 'task.status_changed', entity: 'task', entityId: task.id, payload: { status: task.status }, req });
    automations.runEventTriggered({
      trigger: 'TASK_STATUS_CHANGED',
      context: { taskId: task.id, status: task.status, ownerId: task.createdById },
    }).catch(() => {});
    req.app.get('io')?.emit('task.moved', task);
    res.json(task);
  })
);

router.delete('/:id', asyncHandler(async (req, res) => {
  await service.remove(req.params.id, req.user);
  audit.record({ kind: 'task.deleted', entity: 'task', entityId: req.params.id, req });
  req.app.get('io')?.emit('task.deleted', { id: req.params.id });
  res.status(204).end();
}));

router.post(
  '/:id/comments',
  validate({ body: Joi.object({ body: Joi.string().min(1).max(8000).required() }) }),
  asyncHandler(async (req, res) => {
    const comment = await service.addComment({ taskId: req.params.id, user: req.user, body: req.body.body });
    req.app.get('io')?.emit('task.comment', { taskId: req.params.id, comment });
    res.status(201).json(comment);
  })
);

router.post(
  '/:id/subtasks',
  validate({ body: Joi.object({ title: Joi.string().min(1).max(240).required() }) }),
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.addSubtask({ taskId: req.params.id, title: req.body.title }))
  )
);

router.patch(
  '/subtasks/:id',
  validate({ body: Joi.object({ done: Joi.boolean().required() }) }),
  asyncHandler(async (req, res) =>
    res.json(await service.toggleSubtask({ id: req.params.id, done: req.body.done }))
  )
);

// ---------------------------------------------------------------------------
// Assignment lifecycle endpoints — accept / decline / complete
// ---------------------------------------------------------------------------

/**
 * Shared post-transition step: notify the task creator, emit a socket event
 * to their user-room, write an audit log. Keeps the three handlers tight.
 */
async function _notifyCreator({ row, kind, title, body, req, payload = {} }) {
  const creatorId = row.task.createdById;
  if (creatorId && creatorId !== row.userId) {
    notifications.notify({
      userId: creatorId,
      kind: 'TASK',
      title,
      body,
      data: { taskId: row.taskId, assigneeId: row.userId, state: row.state, ...payload },
    }).catch(() => {});
  }
  // Also notify the assignee themselves with their own receipt — gives them
  // an explicit record of every transition in the notification feed.
  notifications.notify({
    userId: row.userId,
    kind: 'TASK',
    title,
    body,
    data: { taskId: row.taskId, state: row.state, ...payload },
  }).catch(() => {});

  audit.record({ kind, entity: 'task', entityId: row.taskId, payload: { userId: row.userId, ...payload }, req });

  const io = req.app.get('io');
  io?.emit('task.assignment.changed', {
    taskId: row.taskId,
    userId: row.userId,
    state: row.state,
    score: row.score ?? null,
    scoreReason: row.scoreReason ?? null,
  });
}

router.post(
  '/:id/accept',
  asyncHandler(async (req, res) => {
    const row = await service.accept({ taskId: req.params.id, userId: req.user.id });
    await _notifyCreator({
      row, kind: 'task.accepted', req,
      title: `${req.user.name} accepted your task`,
      body: row.task.title,
    });
    res.json(row);
  })
);

router.post(
  '/:id/decline',
  asyncHandler(async (req, res) => {
    const row = await service.decline({ taskId: req.params.id, userId: req.user.id });
    await _notifyCreator({
      row, kind: 'task.declined', req,
      title: `${req.user.name} declined your task`,
      body: row.task.title,
    });
    res.json(row);
  })
);

router.post(
  '/:id/complete',
  asyncHandler(async (req, res) => {
    const { assignment: row, autoCompleted } = await service.complete({
      taskId: req.params.id,
      userId: req.user.id,
    });
    await _notifyCreator({
      row,
      kind: 'task.completed',
      req,
      title: `${req.user.name} completed your task`,
      body: `${row.task.title} · score ${row.score}/100 · ${row.scoreReason}`,
      payload: { score: row.score, autoCompleted },
    });
    res.json({ ...row, autoCompleted });
  })
);

module.exports = router;
