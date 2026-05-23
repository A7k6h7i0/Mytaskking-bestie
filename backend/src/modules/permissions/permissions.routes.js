'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const rbac = require('../../services/rbac');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

router.get(
  '/mine',
  asyncHandler(async (req, res) => res.json(await rbac.listEffective(req.user)))
);

router.get(
  '/grants',
  requireAdmin,
  validate({
    query: Joi.object({ userId: Joi.string(), roleName: Joi.string(), key: Joi.string() }),
  }),
  asyncHandler(async (req, res) => {
    const where = {
      ...(req.query.userId ? { userId: req.query.userId } : {}),
      ...(req.query.roleName ? { roleName: req.query.roleName } : {}),
      ...(req.query.key ? { key: { contains: req.query.key } } : {}),
    };
    const items = await prisma.permissionGrant.findMany({ where, orderBy: { createdAt: 'desc' } });
    res.json({ items });
  })
);

router.post(
  '/grants',
  requireAdmin,
  validate({
    body: Joi.object({
      userId: Joi.string().allow(null),
      roleName: Joi.string().valid('SUPER_ADMIN', 'ADMIN', 'MANAGER', 'PROJECT_COORDINATOR_MANAGER', 'EMPLOYEE', 'TELECALLER', 'CLIENT').allow(null),
      key: Joi.string().required(),
      allow: Joi.boolean().default(true),
      scope: Joi.any(),
    }).xor('userId', 'roleName'),
  }),
  asyncHandler(async (req, res) => {
    const grant = await prisma.permissionGrant.create({ data: req.body });
    audit.record({ kind: 'permission.granted', entity: 'permission', entityId: grant.id, payload: req.body, req });
    res.status(201).json(grant);
  })
);

router.delete(
  '/grants/:id',
  requireAdmin,
  asyncHandler(async (req, res) => {
    await prisma.permissionGrant.delete({ where: { id: req.params.id } }).catch(() => {});
    audit.record({ kind: 'permission.revoked', entity: 'permission', entityId: req.params.id, req });
    res.status(204).end();
  })
);

router.get(
  '/roles',
  requireAdmin,
  asyncHandler(async (_req, res) => {
    const items = await prisma.roleTemplate.findMany({ orderBy: { name: 'asc' } });
    res.json({ items });
  })
);

router.post(
  '/roles',
  requireAdmin,
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(64).required(),
      description: Joi.string().allow('', null),
      permissions: Joi.array().items(Joi.string()).default([]),
    }),
  }),
  asyncHandler(async (req, res) => {
    const tmpl = await prisma.roleTemplate.create({ data: req.body });
    audit.record({ kind: 'role.created', entity: 'role_template', entityId: tmpl.id, req });
    res.status(201).json(tmpl);
  })
);

router.patch(
  '/roles/:id',
  requireAdmin,
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(64),
      description: Joi.string().allow('', null),
      permissions: Joi.array().items(Joi.string()),
    }),
  }),
  asyncHandler(async (req, res) => {
    const tmpl = await prisma.roleTemplate.update({ where: { id: req.params.id }, data: req.body });
    res.json(tmpl);
  })
);

router.delete(
  '/roles/:id',
  requireAdmin,
  asyncHandler(async (req, res) => {
    const tmpl = await prisma.roleTemplate.findUnique({ where: { id: req.params.id } });
    if (tmpl?.builtin) return res.status(400).json({ error: { code: 'builtin_role', message: 'Built-in roles cannot be deleted' } });
    await prisma.roleTemplate.delete({ where: { id: req.params.id } }).catch(() => {});
    res.status(204).end();
  })
);

module.exports = router;
