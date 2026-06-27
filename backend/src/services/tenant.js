'use strict';

const prisma = require('../database/prisma');
const logger = require('../utils/logger');
const { Forbidden, NotFound } = require('../utils/errors');

/**
 * Lark-style multi-tenancy: each organisation is an isolated workspace.
 * Platform SUPER_ADMIN (Lakshmiraj) uses /tenants APIs to manage all orgs.
 */

const MULTI_TENANT = process.env.MULTI_TENANT !== 'false';
const DEFAULT_TENANT_ID = process.env.DEFAULT_TENANT_ID || 'default';

function isPlatformSuperAdmin(user) {
  return user?.role === 'SUPER_ADMIN';
}

function resolveTenantId(req) {
  if (!req?.user) return null;
  return req.tenantId || req.user.tenantId || DEFAULT_TENANT_ID;
}

async function ensureDefaultTenant() {
  if (await prisma.tenant.findUnique({ where: { id: DEFAULT_TENANT_ID } })) return;
  try {
    await prisma.tenant.create({
      data: {
        id: DEFAULT_TENANT_ID,
        slug: 'default',
        name: process.env.WORKSPACE_NAME || 'MyTaskKing',
        status: 'ACTIVE',
        storagePrefix: 'default',
      },
    });
    logger.info({ id: DEFAULT_TENANT_ID }, 'tenant.default.created');
  } catch {
    // race: another worker created it first
  }
}

function attachTenant(req, _res, next) {
  if (!req.user) return next();
  req.tenantId = MULTI_TENANT ? (req.user.tenantId || DEFAULT_TENANT_ID) : null;
  next();
}

/**
 * Scope Prisma queries to the caller's organisation.
 * Platform routes pass { bypass: true } for SUPER_ADMIN cross-org reads.
 */
function scopedWhere(req, where = {}, { bypass = false } = {}) {
  if (!MULTI_TENANT) return where;
  if (bypass && isPlatformSuperAdmin(req.user)) return where;
  const tenantId = resolveTenantId(req);
  if (!tenantId) return where;
  return { ...where, tenantId };
}

/** Stamp tenantId on create payloads. */
function withTenant(req, data) {
  if (!MULTI_TENANT) return data;
  const tenantId = resolveTenantId(req);
  if (!tenantId) return data;
  return { ...data, tenantId };
}

function slugify(input) {
  return String(input || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
}

async function findTenantBySlug(slug) {
  const normalized = slugify(slug);
  if (!normalized) return null;
  return prisma.tenant.findUnique({ where: { slug: normalized } });
}

async function findUserForLogin({ tenantSlug, userId }) {
  const slug = tenantSlug ? slugify(tenantSlug) : DEFAULT_TENANT_ID;
  let tenant;
  if (slug === DEFAULT_TENANT_ID || slug === 'default') {
    tenant = await prisma.tenant.findUnique({ where: { id: DEFAULT_TENANT_ID } });
  } else {
    tenant = await prisma.tenant.findUnique({ where: { slug } });
  }
  if (!tenant) return { tenant: null, user: null };
  if (tenant.status === 'SUSPENDED') return { tenant, user: null };

  const user = await prisma.user.findUnique({
    where: { tenantId_userId: { tenantId: tenant.id, userId } },
  });
  return { tenant, user };
}

async function assertSameTenant(req, userId) {
  if (!MULTI_TENANT || !userId) return;
  const actorTenant = resolveTenantId(req);
  const target = await prisma.user.findUnique({
    where: { id: userId },
    select: { tenantId: true },
  });
  if (!target) throw NotFound('User not found');
  if (target.tenantId !== actorTenant && !isPlatformSuperAdmin(req.user)) {
    throw Forbidden('That user belongs to another organisation');
  }
}

async function filterUserIdsInTenant(req, userIds) {
  if (!MULTI_TENANT || !userIds?.length) return userIds || [];
  const tenantId = resolveTenantId(req);
  const rows = await prisma.user.findMany({
    where: { id: { in: userIds }, tenantId },
    select: { id: true },
  });
  return rows.map((r) => r.id);
}

module.exports = {
  MULTI_TENANT,
  DEFAULT_TENANT_ID,
  isPlatformSuperAdmin,
  resolveTenantId,
  ensureDefaultTenant,
  attachTenant,
  scopedWhere,
  withTenant,
  slugify,
  findTenantBySlug,
  findUserForLogin,
  assertSameTenant,
  filterUserIdsInTenant,
};
