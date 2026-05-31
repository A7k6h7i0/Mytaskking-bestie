'use strict';

const prisma = require('../database/prisma');
const logger = require('../utils/logger');

/**
 * Tenant scoping helper — single source of truth for "which workspace is the
 * caller currently operating in?".
 *
 * The platform ships single-tenant today: the env flag `MULTI_TENANT` is off
 * and every request resolves to a synthetic default tenant. Turning the flag
 * on starts using `User.tenantId` for scoping. All Prisma `where` clauses in
 * modules should pass through `scopedWhere` so they stay correct in both
 * modes without changes.
 */

const MULTI_TENANT = process.env.MULTI_TENANT === 'true';
const DEFAULT_TENANT_ID = process.env.DEFAULT_TENANT_ID || 'default';

async function ensureDefaultTenant() {
  if (await prisma.tenant.findUnique({ where: { id: DEFAULT_TENANT_ID } })) return;
  try {
    await prisma.tenant.create({
      data: {
        id: DEFAULT_TENANT_ID,
        slug: 'default',
        name: process.env.WORKSPACE_NAME || 'MyTaskKing',
      },
    });
    logger.info({ id: DEFAULT_TENANT_ID }, 'tenant.default.created');
  } catch {
    // race: another worker created it first — ignore
  }
}

function attachTenant(req, _res, next) {
  if (!req.user) return next();
  req.tenantId = MULTI_TENANT ? (req.user.tenantId || DEFAULT_TENANT_ID) : null;
  next();
}

/**
 * Adds `{ tenantId }` to a Prisma `where` clause when multi-tenancy is on.
 * Returns the original `where` unchanged in single-tenant mode.
 *
 *   await prisma.task.findMany({ where: scopedWhere(req, { status: 'TODO' }) })
 */
function scopedWhere(req, where = {}) {
  if (!MULTI_TENANT) return where;
  if (!req.tenantId) return where;
  return { ...where, tenantId: req.tenantId };
}

/** Attach the caller's tenantId to a Prisma `data` payload during create. */
function withTenant(req, data) {
  if (!MULTI_TENANT) return data;
  if (!req.tenantId) return data;
  return { ...data, tenantId: req.tenantId };
}

module.exports = {
  MULTI_TENANT,
  DEFAULT_TENANT_ID,
  ensureDefaultTenant,
  attachTenant,
  scopedWhere,
  withTenant,
};
