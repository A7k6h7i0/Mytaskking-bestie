'use strict';

const { Router } = require('express');
const Joi = require('joi');
const validate = require('../../middleware/validate');
const asyncHandler = require('../../utils/asyncHandler');
const { requireAuth, requireAdmin, requireInternal } = require('../../middleware/auth');
const service = require('./employees.service');
const audit = require('../../services/audit');

const router = Router();

const EmployeeRole = Joi.string().valid('ADMIN', 'MANAGER', 'PROJECT_COORDINATOR_MANAGER', 'EMPLOYEE', 'TELECALLER');

router.use(requireAuth);

router.get(
  '/',
  requireInternal,
  validate({
    query: Joi.object({
      q: Joi.string().allow(''),
      role: EmployeeRole.optional(),
      status: Joi.string().valid('ACTIVE', 'SUSPENDED', 'EXPIRED').optional(),
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(25),
    }),
  }),
  asyncHandler(async (req, res) => {
    res.json(await service.list(req.query));
  })
);

router.get(
  '/:id',
  requireInternal,
  asyncHandler(async (req, res) => res.json(await service.getById(req.params.id)))
);

router.post(
  '/',
  requireAdmin,
  validate({
    body: Joi.object({
      userId: Joi.string().trim().min(2).max(64).required(),
      password: Joi.string().min(8).max(200).required(),
      name: Joi.string().min(1).max(120).required(),
      role: EmployeeRole.required(),
      customTitle: Joi.string().max(120).allow('', null),
      email: Joi.string().email().allow('', null),
      phone: Joi.string().allow('', null),
      avatarUrl: Joi.string().uri().allow('', null),
      departmentId: Joi.string().allow('', null),
      supervisorIds: Joi.array().items(Joi.string()).default([]),
    }),
  }),
  asyncHandler(async (req, res) => {
    const e = await service.create(req.body, req.user.id);
    audit.record({ kind: 'employee.created', entity: 'user', entityId: e.id, payload: { role: e.role }, req });
    res.status(201).json(e);
  })
);

router.patch(
  '/:id',
  requireAdmin,
  validate({
    body: Joi.object({
      userId: Joi.string().trim().min(2).max(64),
      name: Joi.string().min(1).max(120),
      role: EmployeeRole,
      customTitle: Joi.string().max(120).allow('', null),
      email: Joi.string().email().allow('', null),
      phone: Joi.string().allow('', null),
      avatarUrl: Joi.string().uri().allow('', null),
      departmentId: Joi.string().allow('', null),
      password: Joi.string().min(8).max(200),
      status: Joi.string().valid('ACTIVE', 'SUSPENDED'),
      supervisorIds: Joi.array().items(Joi.string()),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.update(req.params.id, req.body)))
);

router.post(
  '/:id/suspend',
  requireAdmin,
  asyncHandler(async (req, res) => res.json(await service.setStatus(req.params.id, 'SUSPENDED')))
);

router.post(
  '/:id/activate',
  requireAdmin,
  asyncHandler(async (req, res) => res.json(await service.setStatus(req.params.id, 'ACTIVE')))
);

router.delete(
  '/:id',
  requireAdmin,
  asyncHandler(async (req, res) => {
    await service.remove(req.params.id);
    audit.record({ kind: 'employee.deleted', entity: 'user', entityId: req.params.id, req });
    res.status(204).end();
  })
);

module.exports = router;
