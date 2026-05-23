'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./calls.service');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

router.post(
  '/initiate',
  validate({
    body: Joi.object({
      participantIds: Joi.array().items(Joi.string()).min(1).required(),
      kind: Joi.string().valid('ONE_TO_ONE', 'GROUP'),
      channelId: Joi.string().allow(null, ''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const result = await service.initiate({
      initiator: req.user,
      participantIds: req.body.participantIds,
      kind: req.body.kind,
      channelId: req.body.channelId,
    });
    audit.record({
      kind: 'call.initiated',
      entity: 'call',
      entityId: result.call.id,
      payload: { kind: result.call.kind, participants: req.body.participantIds.length + 1 },
      req,
    });
    const io = req.app.get('io');
    for (const p of result.call.participants) {
      io?.to(`user:${p.userId}`).emit('call.incoming', {
        call: result.call,
        token: result.tokens[p.userId],
      });
    }
    res.status(201).json(result);
  })
);

router.get(
  '/:id/token',
  asyncHandler(async (req, res) => res.json(await service.tokenFor({ callId: req.params.id, user: req.user })))
);

router.post('/:id/join', asyncHandler(async (req, res) => {
  const call = await service.join({ callId: req.params.id, user: req.user });
  req.app.get('io')?.emit('call.participant.joined', { callId: call.id, userId: req.user.id });
  res.json(call);
}));

router.post('/:id/leave', asyncHandler(async (req, res) => {
  const call = await service.leave({ callId: req.params.id, user: req.user });
  req.app.get('io')?.emit('call.participant.left', { callId: call.id, userId: req.user.id });
  res.json(call);
}));

router.post('/:id/decline', asyncHandler(async (req, res) => {
  const call = await service.decline({ callId: req.params.id, user: req.user });
  req.app.get('io')?.emit('call.declined', { callId: call.id, userId: req.user.id, status: call.status });
  res.json(call);
}));

router.post(
  '/:id/participants',
  validate({
    body: Joi.object({
      userId: Joi.string(),
      userIds: Joi.array().items(Joi.string()).min(1),
    }).or('userId', 'userIds'),
  }),
  asyncHandler(async (req, res) => {
    const userIds = Array.from(
      new Set([
        ...(req.body.userId ? [req.body.userId] : []),
        ...((Array.isArray(req.body.userIds) ? req.body.userIds : [])),
      ])
    );
    const result = await service.addParticipant({
      callId: req.params.id,
      userIds,
      actor: req.user,
    });
    for (const userId of userIds) {
      req.app.get('io')?.to(`user:${userId}`).emit('call.invited', {
        call: result.call,
        token: result.tokens[userId],
      });
    }
    res.json(result);
  })
);

router.post(
  '/:id/mute',
  validate({ body: Joi.object({ muted: Joi.boolean().required() }) }),
  asyncHandler(async (req, res) => {
    await service.setMuted({ callId: req.params.id, user: req.user, muted: req.body.muted });
    req.app.get('io')?.emit('call.participant.muted', {
      callId: req.params.id,
      userId: req.user.id,
      muted: req.body.muted,
    });
    res.json({ ok: true });
  })
);

router.get(
  '/history',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(25),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.history({ user: req.user, ...req.query })))
);

// ----- screen sharing -----
// Agora screen share uses a separate logical UID on the same channelName so
// the publisher's camera/mic stream and screen stream are independently
// subscribable. We mint a new token with a screen-only UID.
router.post(
  '/:id/screen-share/token',
  asyncHandler(async (req, res) => {
    const result = await service.screenShareToken({ callId: req.params.id, user: req.user });
    req.app.get('io')?.emit('call.screen_share.started', { callId: req.params.id, userId: req.user.id });
    res.json(result);
  })
);

router.post(
  '/:id/screen-share/stop',
  asyncHandler(async (req, res) => {
    req.app.get('io')?.emit('call.screen_share.stopped', { callId: req.params.id, userId: req.user.id });
    res.json({ ok: true });
  })
);

// ----- raise hand / lower hand -----
router.post(
  '/:id/raise-hand',
  validate({ body: Joi.object({ raised: Joi.boolean().required() }) }),
  asyncHandler(async (req, res) => {
    req.app.get('io')?.emit('call.hand_raised', {
      callId: req.params.id,
      userId: req.user.id,
      raised: req.body.raised,
    });
    res.json({ ok: true });
  })
);

// ----- active speaker telemetry -----
// Clients post these periodically; server fans them out so other participants
// can highlight the active speaker. Volume is 0–255 (Agora's report scale).
router.post(
  '/:id/speaking',
  validate({ body: Joi.object({ volume: Joi.number().min(0).max(255).required() }) }),
  asyncHandler(async (req, res) => {
    req.app.get('io')?.emit('call.speaking', {
      callId: req.params.id,
      userId: req.user.id,
      volume: req.body.volume,
    });
    res.json({ ok: true });
  })
);

module.exports = router;
