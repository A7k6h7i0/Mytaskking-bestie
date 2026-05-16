'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const service = require('../../services/sessions');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

router.get(
  '/mine',
  asyncHandler(async (req, res) => res.json({ items: await service.listForUser(req.user.id) }))
);

router.get(
  '/users/:userId',
  requireAdmin,
  asyncHandler(async (req, res) => res.json({ items: await service.listForUser(req.params.userId) }))
);

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await service.revoke({ id: req.params.id, actor: req.user, force: false });
    audit.record({ kind: 'session.revoked', entity: 'session', entityId: req.params.id, req });
    res.json({ ok: true });
  })
);

router.post(
  '/users/:userId/force-logout',
  requireAdmin,
  validate({ body: Joi.object({ exceptCurrent: Joi.boolean().default(false) }) }),
  asyncHandler(async (req, res) => {
    const result = await service.revokeAll({
      userId: req.params.userId,
      actor: req.user,
      force: true,
      exceptSessionId: null,
    });
    audit.record({
      kind: 'session.force_logout',
      entity: 'user',
      entityId: req.params.userId,
      payload: { revoked: result.revoked },
      req,
    });
    res.json(result);
  })
);

router.post(
  '/mine/sign-out-everywhere',
  asyncHandler(async (req, res) => {
    const result = await service.revokeAll({ userId: req.user.id, actor: req.user, force: false });
    res.json(result);
  })
);

module.exports = router;
