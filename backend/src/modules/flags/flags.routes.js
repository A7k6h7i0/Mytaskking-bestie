'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const flags = require('../../services/featureFlags');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

const Rollout = Joi.string().valid('GLOBAL', 'ROLE', 'USER', 'TENANT', 'PERCENT');

// Anyone can ask "which flags apply to me?" — the frontend uses this to hide
// or show experimental UI.
router.get(
  '/mine',
  asyncHandler(async (req, res) => res.json(await flags.listForUser(req.user)))
);

router.get(
  '/',
  requireAdmin,
  asyncHandler(async (_req, res) => res.json({ items: await flags.listAll() }))
);

router.put(
  '/:key',
  requireAdmin,
  validate({
    body: Joi.object({
      description: Joi.string().allow('', null),
      enabled: Joi.boolean(),
      rollout: Rollout,
      payload: Joi.any(),
      percent: Joi.number().integer().min(0).max(100).allow(null),
      roles: Joi.array().items(Joi.string()),
      tenantIds: Joi.array().items(Joi.string()),
    }),
  }),
  asyncHandler(async (req, res) => {
    const row = await flags.upsert(req.params.key, req.body);
    audit.record({ kind: 'flag.upserted', entity: 'flag', entityId: req.params.key, payload: req.body, req });
    res.json(row);
  })
);

router.post(
  '/:key/assign',
  requireAdmin,
  validate({ body: Joi.object({ userId: Joi.string().required(), enabled: Joi.boolean().default(true) }) }),
  asyncHandler(async (req, res) => {
    const row = await flags.assign({ flagKey: req.params.key, ...req.body });
    audit.record({ kind: 'flag.assigned', entity: 'flag', entityId: req.params.key, payload: req.body, req });
    res.json(row);
  })
);

module.exports = router;
