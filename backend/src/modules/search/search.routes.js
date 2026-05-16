'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const adapter = require('../../services/searchAdapter');

const router = Router();
router.use(requireAuth);

/**
 * Global workspace search. Delegates to the configured search adapter
 * (Postgres by default, Meilisearch/Elasticsearch when wired). Scope rules
 * (clients see only their assigned data, telecallers see their own leads,
 * etc.) live inside the adapter so swapping engines doesn't change the
 * authorization story.
 */
router.get(
  '/',
  validate({
    query: Joi.object({
      q: Joi.string().min(1).max(200).required(),
      perEntity: Joi.number().integer().min(1).max(20).default(6),
      kinds: Joi.string().optional(),
      recentBoost: Joi.boolean().default(true),
    }),
  }),
  asyncHandler(async (req, res) => {
    const kinds = req.query.kinds
      ? req.query.kinds.split(',').map((s) => s.trim()).filter(Boolean)
      : null;
    const result = await adapter.search({
      user: req.user,
      q: req.query.q.trim(),
      perEntity: req.query.perEntity,
      recentBoost: req.query.recentBoost,
      kinds,
    });
    res.json({ q: req.query.q, ...result });
  })
);

module.exports = router;
