'use strict';

const prisma = require('../database/prisma');
const logger = require('../utils/logger');
const { Forbidden, NotFound, BadRequest } = require('../utils/errors');

/**
 * Lark-style multi-tenancy: each organisation is an isolated workspace.
 * Platform SUPER_ADMIN (Lakshmiraj) uses /tenants APIs to manage all orgs.
 */

const MULTI_TENANT = process.env.MULTI_TENANT !== 'false';
const DEFAULT_TENANT_ID = process.env.DEFAULT_TENANT_ID || 'default';

function isPlatformSuperAdmin(user) {
  if (!user || user.role !== 'SUPER_ADMIN') return false;
  if (!MULTI_TENANT) return true;
  return (user.tenantId || DEFAULT_TENANT_ID) === DEFAULT_TENANT_ID;
}

function isSalesHead(user) {
  if (!user || user.role !== 'SALES_HEAD') return false;
  if (!MULTI_TENANT) return true;
  return (user.tenantId || DEFAULT_TENANT_ID) === DEFAULT_TENANT_ID;
}

function isPlatformStaff(user) {
  return isPlatformSuperAdmin(user) || isSalesHead(user);
}

/** Resolved tenant for any authenticated user. */
function userTenantId(user) {
  if (!MULTI_TENANT) return null;
  return user?.tenantId || DEFAULT_TENANT_ID;
}

function isOrgAdmin(user) {
  return !!user && ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
}

/** Org admin powers apply only within the caller's organisation (not cross-tenant). */
function canAdministerTenant(user, resourceTenantId) {
  if (!isOrgAdmin(user)) return false;
  if (!MULTI_TENANT) return true;
  if (isPlatformSuperAdmin(user)) return true;
  const resource = resourceTenantId || DEFAULT_TENANT_ID;
  return userTenantId(user) === resource;
}

function assertSameTenant(user, resourceTenantId) {
  if (!MULTI_TENANT) return;
  const actorTenant = userTenantId(user);
  const resource = resourceTenantId || DEFAULT_TENANT_ID;
  if (actorTenant === resource) return;
  if (isPlatformSuperAdmin(user)) return;
  throw Forbidden('That resource belongs to another organisation');
}

/** Prisma where fragment `{ tenantId }` for models stamped with tenantId. */
function tenantClause(userOrTenantId, where = {}) {
  if (!MULTI_TENANT) return where;
  const tenantId =
    typeof userOrTenantId === 'string'
      ? userOrTenantId || DEFAULT_TENANT_ID
      : userTenantId(userOrTenantId);
  const tenantWhere = { tenantId };
  if (!where || Object.keys(where).length === 0) return tenantWhere;
  return { AND: [tenantWhere, where] };
}

function resolveTenantId(req) {
  if (!req?.user) return null;
  return req.tenantId || req.user.tenantId || DEFAULT_TENANT_ID;
}

async function ensureDefaultTenant() {
  try {
    if (await prisma.tenant.findUnique({ where: { id: DEFAULT_TENANT_ID } })) return;
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
  } catch (err) {
    logger.warn({ err: err.message }, 'tenant.ensure_default.failed');
  }
}

/** Last-resort lookup when Prisma model/DB are out of sync (pre-migration prod). */
async function findUserByLoginIdRaw(userId) {
  const uid = String(userId || '').trim();
  if (!uid) return null;
  try {
    const rows = await prisma.$queryRaw`
      SELECT id, "userId", "passwordHash", role, status, "isClient",
             "accessEndsAt", "tenantId", name, email, phone, "avatarUrl",
             "customTitle", "clientCompany", "accessStartsAt", "createdById",
             "lastSeenAt", "createdAt", "updatedAt", "departmentId"
      FROM "User"
      WHERE LOWER("userId") = LOWER(${uid})
      LIMIT 1
    `;
    const row = rows[0];
    if (row && row.tenantId == null) row.tenantId = DEFAULT_TENANT_ID;
    return row || null;
  } catch (err) {
    if (!String(err.message).includes('tenantId')) {
      logger.warn({ err: err.message }, 'login.raw_user_lookup_failed');
      return null;
    }
    const rows = await prisma.$queryRaw`
      SELECT id, "userId", "passwordHash", role, status, "isClient",
             "accessEndsAt", name, email, phone, "avatarUrl",
             "customTitle", "clientCompany", "accessStartsAt", "createdById",
             "lastSeenAt", "createdAt", "updatedAt", "departmentId"
      FROM "User"
      WHERE LOWER("userId") = LOWER(${uid})
      LIMIT 1
    `;
    const row = rows[0];
    if (row) row.tenantId = DEFAULT_TENANT_ID;
    return row || null;
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
  const normalizedUserId = String(userId || '').trim();
  if (!normalizedUserId) return { tenant: null, user: null };

  const syntheticDefault = () => ({
    id: DEFAULT_TENANT_ID,
    slug: 'default',
    name: process.env.WORKSPACE_NAME || 'MyTaskKing',
    status: 'ACTIVE',
  });

  const wantSlug = tenantSlug ? slugify(tenantSlug) : 'default';
  const isDefaultOrg =
    !tenantSlug || wantSlug === 'default' || wantSlug === DEFAULT_TENANT_ID;

  let tenant = null;
  try {
    await ensureDefaultTenant();
    tenant = isDefaultOrg
      ? await prisma.tenant.findUnique({ where: { id: DEFAULT_TENANT_ID } })
      : await prisma.tenant.findUnique({ where: { slug: wantSlug } });
  } catch (err) {
    logger.warn({ err: err.message }, 'login.tenant_lookup_failed');
  }

  const legacyDb = !tenant;
  if (legacyDb) {
    if (!isDefaultOrg) return { tenant: null, user: null };
    tenant = syntheticDefault();
  } else if (tenant.status === 'SUSPENDED') {
    return { tenant, user: null };
  } else if (tenant.status === 'PENDING') {
    return { tenant, user: null, pendingApproval: true };
  }

  let user = null;
  if (!legacyDb) {
    try {
      user = await prisma.user.findUnique({
        where: { tenantId_userId: { tenantId: tenant.id, userId: normalizedUserId } },
      });
    } catch (err) {
      logger.warn({ err: err.message }, 'login.composite_user_lookup_failed');
    }
  }

  if (!user) {
    try {
      user = await prisma.user.findFirst({
        where: { userId: { equals: normalizedUserId, mode: 'insensitive' } },
      });
      if (user && user.tenantId && user.tenantId !== tenant.id) {
        user = null;
      }
    } catch (err) {
      logger.warn({ err: err.message }, 'login.legacy_user_lookup_failed');
    }
  }

  if (!user) {
    user = await findUserByLoginIdRaw(normalizedUserId);
    if (user && user.tenantId && user.tenantId !== tenant.id) {
      user = null;
    }
  }

  return { tenant, user };
}

async function assertUserSameTenant(req, userId) {
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

async function filterUserIdsForUser(user, userIds) {
  if (!MULTI_TENANT || !userIds?.length) return userIds || [];
  const tenantId = userTenantId(user);
  const rows = await prisma.user.findMany({
    where: { id: { in: userIds }, tenantId },
    select: { id: true },
  });
  return rows.map((r) => r.id);
}

async function assertUserIdsForUser(user, userIds) {
  const ids = Array.from(new Set((userIds || []).filter(Boolean)));
  const filtered = await filterUserIdsForUser(user, ids);
  if (filtered.length !== ids.length) {
    throw BadRequest('One or more users belong to another organisation');
  }
  return filtered;
}

async function assertDepartmentInOrg(req, departmentId) {
  if (!MULTI_TENANT || !departmentId) return;
  const dept = await prisma.department.findUnique({
    where: { id: departmentId },
    select: { tenantId: true },
  });
  if (!dept || dept.tenantId !== resolveTenantId(req)) {
    throw BadRequest('Department belongs to another organisation');
  }
}

function stripClientTenantFields(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return input;
  const out = { ...input };
  delete out.tenantId;
  delete out.organizationId;
  delete out.orgId;
  delete out.tenantSlug;
  return out;
}

function orgSettingScope(req, scope) {
  if (!MULTI_TENANT) return scope;
  return `org:${resolveTenantId(req)}:${scope}`;
}

function assertResourceInOrg(req, resourceTenantId, message = 'Resource belongs to another organisation') {
  if (!MULTI_TENANT) return;
  const actorTenant = resolveTenantId(req);
  const resource = resourceTenantId || DEFAULT_TENANT_ID;
  if (actorTenant === resource) return;
  if (isPlatformSuperAdmin(req.user)) return;
  throw Forbidden(message);
}

module.exports = {
  MULTI_TENANT,
  DEFAULT_TENANT_ID,
  isPlatformSuperAdmin,
  isSalesHead,
  isPlatformStaff,
  userTenantId,
  isOrgAdmin,
  canAdministerTenant,
  assertSameTenant,
  tenantClause,
  resolveTenantId,
  ensureDefaultTenant,
  attachTenant,
  scopedWhere,
  withTenant,
  slugify,
  findTenantBySlug,
  findUserForLogin,
  filterUserIdsInTenant,
  filterUserIdsForUser,
  assertUserIdsForUser,
  assertDepartmentInOrg,
  stripClientTenantFields,
  orgSettingScope,
  assertResourceInOrg,
  assertUserSameTenant,
};
