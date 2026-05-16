'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./tasks.service');
const audit = require('../../services/audit');
const automations = require('../../services/automations');

const router = Router();
router.use(requireAuth);

const Status = Joi.string().valid('BACKLOG', 'TODO', 'IN_PROGRESS', 'REVIEW', 'DONE', 'CANCELLED');
const Priority = Joi.string().valid('LOW', 'MEDIUM', 'HIGH', 'URGENT');

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

router.get('/:id', asyncHandler(async (req, res) => res.json(await service.getById(req.params.id, req.user))));

router.post(
  '/',
  validate({
    body: Joi.object({
      title: Joi.string().min(1).max(240).required(),
      description: Joi.string().max(8000).allow('', null),
      status: Status,
      priority: Priority,
      dueAt: Joi.date().iso(),
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
    const task = await service.update(req.params.id, req.body, req.user);
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

module.exports = router;
