'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

// ----- themes (tenant-scoped, all users can read; admins can write) -----

router.get(
  '/themes',
  asyncHandler(async (req, res) => {
    const items = await prisma.workspaceTheme.findMany({
      where: { OR: [{ tenantId: req.user.tenantId || 'default' }, { tenantId: null }] },
      orderBy: { isDefault: 'desc' },
    });
    res.json({ items });
  })
);

router.post(
  '/themes',
  requireAdmin,
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(80).required(),
      mode: Joi.string().valid('light', 'dark').default('light'),
      tokens: Joi.object().required(),
      isDefault: Joi.boolean().default(false),
    }),
  }),
  asyncHandler(async (req, res) => {
    const theme = await prisma.workspaceTheme.create({
      data: { ...req.body, tenantId: req.user.tenantId || null },
    });
    if (req.body.isDefault) {
      await prisma.workspaceTheme.updateMany({
        where: { tenantId: req.user.tenantId || null, id: { not: theme.id } },
        data: { isDefault: false },
      });
    }
    audit.record({ kind: 'theme.created', entity: 'theme', entityId: theme.id, req });
    res.status(201).json(theme);
  })
);

router.delete(
  '/themes/:id',
  requireAdmin,
  asyncHandler(async (req, res) => {
    await prisma.workspaceTheme.delete({ where: { id: req.params.id } }).catch(() => {});
    res.status(204).end();
  })
);

// ----- dashboard widgets (per-user) -----

router.get(
  '/widgets',
  asyncHandler(async (req, res) => {
    const items = await prisma.dashboardWidget.findMany({
      where: { userId: req.user.id, visible: true },
      orderBy: { position: 'asc' },
    });
    res.json({ items });
  })
);

router.put(
  '/widgets',
  validate({
    body: Joi.object({
      widgets: Joi.array().items(
        Joi.object({
          id: Joi.string().optional(),
          kind: Joi.string().required(),
          config: Joi.any(),
          position: Joi.number().integer(),
          visible: Joi.boolean(),
        })
      ).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    // Replace-the-set semantics: delete missing rows, upsert the rest.
    const incoming = req.body.widgets;
    const existing = await prisma.dashboardWidget.findMany({ where: { userId: req.user.id } });
    const keepIds = new Set(incoming.filter((w) => w.id).map((w) => w.id));
    const toDelete = existing.filter((w) => !keepIds.has(w.id)).map((w) => w.id);

    await prisma.$transaction([
      ...(toDelete.length ? [prisma.dashboardWidget.deleteMany({ where: { id: { in: toDelete } } })] : []),
      ...incoming.map((w, i) =>
        w.id
          ? prisma.dashboardWidget.update({
              where: { id: w.id },
              data: { kind: w.kind, config: w.config, position: w.position ?? i, visible: w.visible ?? true },
            })
          : prisma.dashboardWidget.create({
              data: { userId: req.user.id, kind: w.kind, config: w.config, position: w.position ?? i, visible: w.visible ?? true },
            })
      ),
    ]);

    const items = await prisma.dashboardWidget.findMany({
      where: { userId: req.user.id },
      orderBy: { position: 'asc' },
    });
    res.json({ items });
  })
);

module.exports = router;
