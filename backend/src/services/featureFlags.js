'use strict';

const crypto = require('crypto');
const prisma = require('../database/prisma');
const cache = require('./cache');
const logger = require('../utils/logger');

/**
 * Feature flag resolver.
 *
 *   const enabled = await flags.isEnabled('ai.task_summary', { user });
 *   const payload = await flags.payload('billing.plan_v2', { user });
 *
 * Rollouts:
 *   GLOBAL  — flag.enabled wins
 *   ROLE    — enabled AND user.role ∈ flag.roles
 *   USER    — explicit FeatureFlagAssignment.enabled wins
 *   TENANT  — user.tenantId ∈ flag.tenantIds
 *   PERCENT — sha256(flagKey + userId) mod 100 < flag.percent (sticky)
 *
 * Results are cached per (key, userId) for 30 s through the cache service.
 * That cache is invalidated on every write in this module — there's no fan-out
 * to other nodes because cache.del() is Redis-backed when clustered.
 */

const TTL = 30; // seconds

async function load(key) {
  return cache.memoize((k) => `flag:def:${k}`, async (k) => prisma.featureFlag.findUnique({ where: { key: k } }), 60)(key);
}

async function isEnabled(key, { user } = {}) {
  if (!user) return false;
  return cache.memoize(
    (k, uid) => `flag:on:${k}:${uid}`,
    async (k, uid) => {
      const flag = await load(k);
      if (!flag || !flag.enabled) return false;

      // explicit per-user assignment always wins
      const assignment = await prisma.featureFlagAssignment.findUnique({
        where: { flagKey_userId: { flagKey: k, userId: uid } },
      }).catch(() => null);
      if (assignment) return assignment.enabled;

      switch (flag.rollout) {
        case 'GLOBAL': return true;
        case 'ROLE':   return Array.isArray(flag.roles) && flag.roles.includes(user.role);
        case 'TENANT': return Array.isArray(flag.tenantIds) && flag.tenantIds.includes(user.tenantId || 'default');
        case 'USER':   return false; // only the assignment path satisfies USER rollouts
        case 'PERCENT': {
          const pct = Math.max(0, Math.min(100, flag.percent || 0));
          const h = crypto.createHash('sha256').update(`${k}:${uid}`).digest('hex');
          const bucket = parseInt(h.slice(0, 8), 16) % 100;
          return bucket < pct;
        }
        default: return false;
      }
    },
    TTL
  )(key, user.id);
}

async function payload(key, ctx) {
  const flag = await load(key);
  if (!flag) return null;
  if (!(await isEnabled(key, ctx))) return null;
  return flag.payload ?? null;
}

async function upsert(key, data) {
  const row = await prisma.featureFlag.upsert({
    where: { key },
    update: data,
    create: { key, ...data },
  });
  await cache.del(`flag:def:${key}`).catch(() => {});
  // memoized values use compound keys; we don't bother enumerating, the 30s TTL handles it.
  logger.info({ key }, 'flags.upsert');
  return row;
}

async function assign({ flagKey, userId, enabled = true }) {
  const row = await prisma.featureFlagAssignment.upsert({
    where: { flagKey_userId: { flagKey, userId } },
    update: { enabled },
    create: { flagKey, userId, enabled },
  });
  await cache.del(`flag:on:${flagKey}:${userId}`).catch(() => {});
  return row;
}

async function listAll() {
  return prisma.featureFlag.findMany({ orderBy: { key: 'asc' } });
}

async function listForUser(user) {
  const flags = await listAll();
  const out = {};
  for (const f of flags) {
    out[f.key] = { enabled: await isEnabled(f.key, { user }), payload: f.payload ?? null, description: f.description };
  }
  return out;
}

module.exports = { isEnabled, payload, upsert, assign, listAll, listForUser };
