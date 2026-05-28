'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const service = require('./chat.service');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

// AI grammar / clarity fix — returns a corrected version of the supplied
// text. Used by the composer's "fix grammar" affordance. Returns the
// original unchanged when AI is disabled (noop provider).
router.post(
  '/ai/correct',
  validate({ body: Joi.object({ text: Joi.string().min(1).max(4000).required() }) }),
  asyncHandler(async (req, res) => {
    const ai = require('../../services/ai');
    const prompt = [
      'Correct the grammar, spelling, and clarity of this chat message.',
      'Keep the original meaning, tone, and language. Do not add new content,',
      'greetings, or sign-offs. Return ONLY the corrected message text.',
      '',
      `Message: ${req.body.text}`,
    ].join('\n');
    try {
      const result = await ai.generate({ prompt, maxTokens: 400 });
      const corrected = (result.text || '').trim();
      res.json({
        corrected: corrected.length === 0 ? req.body.text : corrected,
        provider: result.provider,
        changed: corrected.length > 0 && corrected !== req.body.text.trim(),
      });
    } catch (err) {
      res.json({ corrected: req.body.text, error: err.message, changed: false });
    }
  })
);

router.get(
  '/channels/:channelId/messages',
  validate({
    query: Joi.object({
      cursor: Joi.string(),
      limit: Joi.number().integer().min(1).max(100).default(40),
    }),
  }),
  asyncHandler(async (req, res) =>
    res.json(await service.listMessages(req.params.channelId, req.user, req.query))
  )
);

router.post(
  '/channels/:channelId/messages',
  validate({
    body: Joi.object({
      body: Joi.string().max(8000).allow('', null),
      kind: Joi.string().valid('TEXT', 'IMAGE', 'FILE', 'VOICE_NOTE'),
      attachmentIds: Joi.array().items(Joi.string()),
      replyToId: Joi.string().allow(null, ''),
      threadRootId: Joi.string().allow(null, ''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const io = req.app.get('io');
    const message = await service.sendMessage({
      channelId: req.params.channelId,
      user: req.user,
      body: req.body.body || null,
      kind: req.body.kind || 'TEXT',
      attachmentIds: req.body.attachmentIds || [],
      replyToId: req.body.replyToId || null,
      threadRootId: req.body.threadRootId || null,
      io,
    });
    io?.to(`channel:${req.params.channelId}`).emit('chat.message.created', message);
    if (message.threadRootId) {
      io?.to(`channel:${req.params.channelId}`).emit('chat.thread.reply', {
        rootId: message.threadRootId,
        message,
      });
    }
    res.status(201).json(message);
  })
);

router.get(
  '/threads/:rootId',
  validate({
    query: Joi.object({ limit: Joi.number().integer().min(1).max(500).default(100) }),
  }),
  asyncHandler(async (req, res) =>
    res.json(await service.listThread({ rootId: req.params.rootId, user: req.user, limit: req.query.limit }))
  )
);

router.patch(
  '/messages/:id',
  validate({ body: Joi.object({ body: Joi.string().min(1).max(8000).required() }) }),
  asyncHandler(async (req, res) => {
    const message = await service.editMessage({ id: req.params.id, user: req.user, body: req.body.body });
    req.app.get('io')?.to(`channel:${message.channelId}`).emit('chat.message.updated', message);
    res.json(message);
  })
);

router.delete(
  '/messages/:id',
  asyncHandler(async (req, res) => {
    const message = await service.deleteMessage({ id: req.params.id, user: req.user });
    audit.record({ kind: 'message.deleted', entity: 'message', entityId: message.id, payload: { channelId: message.channelId }, req });
    req.app.get('io')?.to(`channel:${message.channelId}`).emit('chat.message.deleted', { id: message.id });
    res.json({ ok: true });
  })
);

router.post(
  '/messages/:id/react',
  validate({ body: Joi.object({ emoji: Joi.string().min(1).max(16).required() }) }),
  asyncHandler(async (req, res) => {
    const r = await service.react({ messageId: req.params.id, userId: req.user.id, emoji: req.body.emoji });
    res.json(r);
  })
);

router.post(
  '/messages/:id/unreact',
  validate({ body: Joi.object({ emoji: Joi.string().min(1).max(16).required() }) }),
  asyncHandler(async (req, res) => {
    await service.unreact({ messageId: req.params.id, userId: req.user.id, emoji: req.body.emoji });
    res.json({ ok: true });
  })
);

router.post('/messages/:id/pin', asyncHandler(async (req, res) =>
  res.json(await service.pin({ messageId: req.params.id, value: true }))
));
router.post('/messages/:id/unpin', asyncHandler(async (req, res) =>
  res.json(await service.pin({ messageId: req.params.id, value: false }))
));

router.post('/channels/:channelId/read', asyncHandler(async (req, res) => {
  await service.markRead({ channelId: req.params.channelId, userId: req.user.id });
  res.json({ ok: true });
}));

// Message receipts — clients post when a message arrived (delivered) and when
// the user actually viewed it (seen). Aggregated for the sender to render ticks.
router.post(
  '/messages/:id/receipt',
  validate({ body: Joi.object({ state: Joi.string().valid('DELIVERED', 'SEEN').required() }) }),
  asyncHandler(async (req, res) => {
    const receipt = await service.recordReceipt({
      messageId: req.params.id,
      userId: req.user.id,
      state: req.body.state,
    });
    if (receipt) {
      req.app
        .get('io')
        ?.to(`channel:${receipt.message.channelId}`)
        .emit('chat.message.receipt', {
          messageId: receipt.message.id,
          userId: req.user.id,
          state: req.body.state,
          at: receipt.at,
        });
    }
    res.json({ ok: true });
  })
);

router.post(
  '/channels/:channelId/receipts/bulk',
  validate({
    body: Joi.object({
      messageIds: Joi.array().items(Joi.string()).min(1).max(200).required(),
      state: Joi.string().valid('DELIVERED', 'SEEN').required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    await service.recordReceiptsBulk({
      messageIds: req.body.messageIds,
      userId: req.user.id,
      state: req.body.state,
    });
    req.app.get('io')?.to(`channel:${req.params.channelId}`).emit('chat.message.receipts.bulk', {
      channelId: req.params.channelId,
      userId: req.user.id,
      state: req.body.state,
      messageIds: req.body.messageIds,
    });
    res.json({ ok: true });
  })
);

module.exports = router;
