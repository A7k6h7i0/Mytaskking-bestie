'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const service = require('./clients.service');
const audit = require('../../services/audit');

const router = Router();

router.use(requireAuth, requireAdmin);

router.get(
  '/',
  validate({
    query: Joi.object({
      q: Joi.string().allow(''),
      status: Joi.string().valid('ACTIVE', 'SUSPENDED', 'EXPIRED'),
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(25),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.list(req.query)))
);

router.get('/:id', asyncHandler(async (req, res) => res.json(await service.getById(req.params.id))));

router.post(
  '/',
  validate({
    body: Joi.object({
      userId: Joi.string().trim().min(2).max(64).required(),
      password: Joi.string().min(8).max(200).required(),
      name: Joi.string().min(1).max(120).required(),
      clientCompany: Joi.string().max(160).allow('', null),
      email: Joi.string().email().allow('', null),
      phone: Joi.string().allow('', null),
      avatarUrl: Joi.string().uri().allow('', null),
      accessStartsAt: Joi.date().iso().optional(),
      accessEndsAt: Joi.date().iso().optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const c = await service.create(req.body, req.user.id);
    audit.record({
      kind: 'client.created',
      entity: 'user',
      entityId: c.id,
      payload: { company: c.clientCompany, accessEndsAt: c.accessEndsAt },
      req,
    });
    res.status(201).json(c);
  })
);

router.patch(
  '/:id',
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(120),
      clientCompany: Joi.string().max(160).allow('', null),
      email: Joi.string().email().allow('', null),
      phone: Joi.string().allow('', null),
      avatarUrl: Joi.string().uri().allow('', null),
      password: Joi.string().min(8).max(200),
      accessStartsAt: Joi.date().iso(),
      accessEndsAt: Joi.date().iso(),
      status: Joi.string().valid('ACTIVE', 'SUSPENDED'),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.update(req.params.id, req.body)))
);

router.post(
  '/:id/extend',
  validate({ body: Joi.object({ accessEndsAt: Joi.date().iso().required() }) }),
  asyncHandler(async (req, res) => {
    const c = await service.extendAccess(req.params.id, req.body.accessEndsAt);
    audit.record({ kind: 'client.access_extended', entity: 'user', entityId: c.id, payload: { until: c.accessEndsAt }, req });
    res.json(c);
  })
);

router.post('/:id/disable', asyncHandler(async (req, res) => {
  const c = await service.disable(req.params.id);
  audit.record({ kind: 'client.disabled', entity: 'user', entityId: c.id, req });
  res.json(c);
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  await service.remove(req.params.id);
  audit.record({ kind: 'client.deleted', entity: 'user', entityId: req.params.id, req });
  res.status(204).end();
}));

module.exports = router;
