'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const service = require('./channels.service');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

router.get('/', asyncHandler(async (req, res) => res.json({ items: await service.listForUser(req.user) })));

router.post(
  '/',
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(120).when('kind', { is: 'DM', then: Joi.optional(), otherwise: Joi.required() }),
      description: Joi.string().max(1000).allow('', null),
      kind: Joi.string().valid('DM', 'GROUP', 'PROJECT', 'ANNOUNCEMENT', 'CLIENT').required(),
      visibility: Joi.string().valid('PUBLIC', 'PRIVATE'),
      memberIds: Joi.array().items(Joi.string()).default([]),
    }),
  }),
  asyncHandler(async (req, res) => {
    const c = await service.create(req.body, req.user);
    audit.record({ kind: 'channel.created', entity: 'channel', entityId: c.id, payload: { kind: c.kind, isClientChannel: c.isClientChannel }, req });
    res.status(201).json(c);
  })
);

router.get('/:id', asyncHandler(async (req, res) => res.json(await service.getById(req.params.id, req.user))));

router.post(
  '/:id/members',
  validate({ body: Joi.object({ memberIds: Joi.array().items(Joi.string()).min(1).required() }) }),
  asyncHandler(async (req, res) => {
    const result = await service.addMembers(req.params.id, req.body.memberIds, req.user);
    audit.record({ kind: 'channel.member_added', entity: 'channel', entityId: req.params.id, payload: { memberIds: req.body.memberIds }, req });
    res.json(result);
  })
);

router.delete(
  '/:id/members/:memberId',
  asyncHandler(async (req, res) => {
    const result = await service.removeMember(req.params.id, req.params.memberId, req.user);
    audit.record({ kind: 'channel.member_removed', entity: 'channel', entityId: req.params.id, payload: { memberId: req.params.memberId }, req });
    res.json(result);
  })
);

router.post('/:id/pin', requireAdmin, asyncHandler(async (req, res) => res.json(await service.pin(req.params.id, true))));
router.post('/:id/unpin', requireAdmin, asyncHandler(async (req, res) => res.json(await service.pin(req.params.id, false))));
router.post('/:id/archive', requireAdmin, asyncHandler(async (req, res) => {
  const c = await service.archive(req.params.id, true);
  audit.record({ kind: 'channel.archived', entity: 'channel', entityId: req.params.id, req });
  res.json(c);
}));
router.post('/:id/unarchive', requireAdmin, asyncHandler(async (req, res) => res.json(await service.archive(req.params.id, false))));

router.patch(
  '/:id/policy',
  validate({
    body: Joi.object({
      defaultCanPost: Joi.boolean(),
      defaultCanUpload: Joi.boolean(),
      defaultCanInvite: Joi.boolean(),
      defaultCanCreateTask: Joi.boolean(),
      retentionDays: Joi.number().integer().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const c = await service.setPolicy(req.params.id, req.body, req.user);
    audit.record({ kind: 'permission.changed', entity: 'channel', entityId: req.params.id, payload: req.body, req });
    res.json(c);
  })
);

router.patch(
  '/:id/members/:memberId',
  validate({
    body: Joi.object({
      memberRole: Joi.string().valid('OWNER', 'ADMIN', 'MODERATOR', 'MEMBER', 'READONLY'),
      canPost: Joi.boolean(),
      canUpload: Joi.boolean(),
      canInvite: Joi.boolean(),
      canCreateTask: Joi.boolean(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const m = await service.setMemberPermissions(req.params.id, req.params.memberId, req.body, req.user);
    audit.record({
      kind: 'permission.changed',
      entity: 'channel_member',
      entityId: m.id,
      payload: { channelId: req.params.id, userId: req.params.memberId, ...req.body },
      req,
    });
    res.json(m);
  })
);

module.exports = router;
