'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const notificationActions = require('../../services/notificationActions');
const chatService = require('../chat/chat.service');
const callsService = require('../calls/calls.service');
const fcm = require('../../services/fcm');
const { NotFound } = require('../../utils/errors');
const service = require('./notifications.service');

const router = Router();

function emitToCallParticipants(io, call, event, payload) {
  for (const p of call?.participants || []) {
    io?.to(`user:${p.userId}`).emit(event, payload);
  }
}

router.post(
  '/actions/chat-reply',
  validate({
    body: Joi.object({
      token: Joi.string().required(),
      body: Joi.string().trim().min(1).max(5000).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const payload = notificationActions.verifyAction(req.body.token, 'chat.reply');
    const user = await prisma.user.findUnique({ where: { id: payload.userId } });
    if (!user) throw NotFound('User not found');
    const message = await chatService.sendMessage({
      channelId: payload.channelId,
      user,
      body: req.body.body,
      io: req.app.get('io'),
    });
    req.app.get('io')?.to(`channel:${payload.channelId}`).emit('chat.message.created', message);
    res.status(201).json({ ok: true, messageId: message.id });
  })
);

router.post(
  '/actions/call-decline',
  validate({
    body: Joi.object({
      token: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const payload = notificationActions.verifyAction(req.body.token, 'call.decline');
    const user = await prisma.user.findUnique({ where: { id: payload.userId } });
    if (!user) throw NotFound('User not found');
    const call = await callsService.decline({ callId: payload.callId, user });
    emitToCallParticipants(req.app.get('io'), call, 'call.declined', {
      callId: call.id,
      userId: user.id,
      status: call.status,
    });
    if (call.status === 'ENDED' || call.status === 'MISSED') {
      emitToCallParticipants(req.app.get('io'), call, 'call.ended', {
        callId: call.id,
        userId: user.id,
        status: call.status,
      });
      await fcm.sendCallEnded(call).catch(() => {/* push is best-effort */});
    }
    res.json({ ok: true, callId: call.id, status: call.status });
  })
);

router.use(requireAuth);

router.get(
  '/',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(30),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.listMine({ user: req.user, ...req.query })))
);

router.post(
  '/read-all',
  asyncHandler(async (req, res) => {
    await service.markAllRead(req.user.id);
    res.json({ ok: true });
  })
);

router.post(
  '/:id/read',
  asyncHandler(async (req, res) => {
    await service.markRead(req.params.id, req.user.id);
    res.json({ ok: true });
  })
);

router.post(
  '/devices',
  validate({
    body: Joi.object({
      token: Joi.string().min(10).required(),
      platform: Joi.string().valid('ANDROID', 'IOS', 'WEB', 'WINDOWS', 'MACOS').required(),
    }),
  }),
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.registerDevice({ userId: req.user.id, ...req.body }))
  )
);

router.delete(
  '/devices/:token',
  asyncHandler(async (req, res) => {
    await service.removeDevice({ token: req.params.token });
    res.status(204).end();
  })
);

router.get(
  '/grouped',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(30),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.groupedListMine({ user: req.user, ...req.query })))
);

router.get(
  '/preferences',
  asyncHandler(async (req, res) => {
    const pref = await service.getPreferences(req.user.id);
    res.json(pref || { channels: {}, muteUntil: null });
  })
);

router.put(
  '/preferences',
  validate({
    body: Joi.object({
      channels: Joi.object().pattern(Joi.string(), Joi.string().valid('all', 'mentions', 'off')),
      muteUntil: Joi.date().iso().allow(null),
      quietHoursStart: Joi.number().integer().min(0).max(23).allow(null),
      quietHoursEnd: Joi.number().integer().min(0).max(23).allow(null),
      timezone: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.setPreferences(req.user.id, req.body)))
);

module.exports = router;
