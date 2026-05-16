'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');
const notifications = require('../notifications/notifications.service');

const router = Router();
router.use(requireAuth);

const Scope = Joi.string().valid('GLOBAL', 'CHANNEL', 'CLIENTS_ONLY', 'EMPLOYEES_ONLY');
const Priority = Joi.string().valid('INFO', 'IMPORTANT', 'URGENT');

const include = {
  author: { select: { id: true, name: true, avatarUrl: true, isClient: true, role: true } },
  channel: { select: { id: true, name: true, kind: true } },
};

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const now = new Date();
    const where = {
      publishAt: { lte: now },
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      ...(req.user.isClient
        ? { scope: { in: ['GLOBAL', 'CLIENTS_ONLY', 'CHANNEL'] } }
        : { scope: { in: ['GLOBAL', 'EMPLOYEES_ONLY', 'CHANNEL'] } }),
    };
    const items = await prisma.announcement.findMany({
      where,
      orderBy: [{ priority: 'desc' }, { publishAt: 'desc' }],
      include,
      take: 50,
    });
    res.json({ items });
  })
);

router.post(
  '/',
  requireAdmin,
  validate({
    body: Joi.object({
      title: Joi.string().min(1).max(240).required(),
      body: Joi.string().min(1).max(8000).required(),
      scope: Scope.default('GLOBAL'),
      priority: Priority.default('INFO'),
      channelId: Joi.string().allow(null, ''),
      publishAt: Joi.date().iso(),
      expiresAt: Joi.date().iso().allow(null),
      pinned: Joi.boolean(),
      notify: Joi.boolean().default(true),
    }),
  }),
  asyncHandler(async (req, res) => {
    const ann = await prisma.announcement.create({
      data: {
        title: req.body.title,
        body: req.body.body,
        scope: req.body.scope,
        priority: req.body.priority,
        channelId: req.body.channelId || null,
        publishAt: req.body.publishAt ? new Date(req.body.publishAt) : new Date(),
        expiresAt: req.body.expiresAt ? new Date(req.body.expiresAt) : null,
        pinned: req.body.pinned ?? true,
        authorId: req.user.id,
      },
      include,
    });

    audit.record({
      kind: 'announcement.published',
      entity: 'announcement',
      entityId: ann.id,
      payload: { scope: ann.scope, priority: ann.priority },
      req,
    });

    req.app.get('io')?.emit('announcement.published', ann);

    if (req.body.notify && ann.publishAt <= new Date()) {
      // Fan out a push notification to users that match scope. Fire-and-forget.
      (async () => {
        const where =
          ann.scope === 'CLIENTS_ONLY' ? { isClient: true }
          : ann.scope === 'EMPLOYEES_ONLY' ? { isClient: false }
          : ann.scope === 'CHANNEL' && ann.channelId
            ? { channelMembers: { some: { channelId: ann.channelId } } }
            : {};
        const targets = await prisma.user.findMany({
          where: { status: 'ACTIVE', ...where },
          select: { id: true },
        });
        await Promise.all(
          targets.map((u) =>
            notifications.notify({
              userId: u.id,
              kind: 'SYSTEM',
              title: ann.title,
              body: ann.body.slice(0, 240),
              data: { announcementId: ann.id, priority: ann.priority },
            }).catch(() => {})
          )
        );
      })();
    }

    res.status(201).json(ann);
  })
);

router.post(
  '/:id/ack',
  asyncHandler(async (req, res) => {
    const ann = await prisma.announcement.findUnique({ where: { id: req.params.id } });
    if (!ann) return res.status(204).end();
    if (!ann.acknowledgedBy.includes(req.user.id)) {
      await prisma.announcement.update({
        where: { id: req.params.id },
        data: { acknowledgedBy: { set: [...ann.acknowledgedBy, req.user.id] } },
      });
    }
    res.json({ ok: true });
  })
);

router.delete(
  '/:id',
  requireAdmin,
  asyncHandler(async (req, res) => {
    await prisma.announcement.delete({ where: { id: req.params.id } }).catch(() => {});
    res.status(204).end();
  })
);

module.exports = router;
