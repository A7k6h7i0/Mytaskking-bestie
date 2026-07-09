'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const audit = require('../../services/audit');
const tenant = require('../../services/tenant');

const router = Router();
router.use(requireAuth);

/**
 * Workspace settings live as scoped key/value rows so adding a new policy
 * doesn't require a migration. Scopes seen so far:
 *   branding      → { logoUrl, primaryColor, name, tagline }
 *   permissions   → policy keys controlling defaults
 *   retention     → { messagesDays, callRecordingsDays, … }
 *   notifications → org-wide opt-outs / mute windows
 *   channelDefaults → defaults for newly-created channels
 *
 * Reads are open to any authenticated user (UIs need branding); writes are admin-only.
 */

router.get(
  '/',
  validate({ query: Joi.object({ scope: Joi.string() }) }),
  asyncHandler(async (req, res) => {
    const where = req.query.scope
      ? { scope: tenant.orgSettingScope(req, req.query.scope) }
      : tenant.MULTI_TENANT
        ? { scope: { startsWith: `org:${tenant.resolveTenantId(req)}:` } }
        : undefined;
    const rows = await prisma.workspaceSetting.findMany({ where });
    const out = {};
    for (const r of rows) {
      const publicScope = tenant.MULTI_TENANT
        ? r.scope.replace(/^org:[^:]+:/, '')
        : r.scope;
      out[publicScope] = out[publicScope] || {};
      out[publicScope][r.key] = r.value;
    }
    res.json(out);
  })
);

router.put(
  '/:scope/:key',
  requireAdmin,
  validate({
    body: Joi.object({ value: Joi.any().required() }),
  }),
  asyncHandler(async (req, res) => {
    const scopedScope = tenant.orgSettingScope(req, req.params.scope);
    const row = await prisma.workspaceSetting.upsert({
      where: { scope_key: { scope: scopedScope, key: req.params.key } },
      update: { value: req.body.value, updatedById: req.user.id },
      create: {
        scope: scopedScope,
        key: req.params.key,
        value: req.body.value,
        updatedById: req.user.id,
      },
    });
    audit.record({
      kind: 'settings.changed',
      entity: 'setting',
      entityId: `${req.params.scope}.${req.params.key}`,
      payload: { value: req.body.value },
      req,
    });
    res.json(row);
  })
);

router.delete(
  '/:scope/:key',
  requireAdmin,
  asyncHandler(async (req, res) => {
    const scopedScope = tenant.orgSettingScope(req, req.params.scope);
    await prisma.workspaceSetting
      .delete({ where: { scope_key: { scope: scopedScope, key: req.params.key } } })
      .catch(() => {});
    audit.record({ kind: 'settings.changed', entity: 'setting', entityId: `${req.params.scope}.${req.params.key}`, payload: { value: null }, req });
    res.json({ ok: true });
  })
);

module.exports = router;
