'use strict';

const tenant = require('../../services/tenant');
const { Forbidden } = require('../../utils/errors');

const MANAGER_ROLES = new Set([
  'SUPER_ADMIN',
  'ADMIN',
  'MANAGER',
  'PROJECT_COORDINATOR_MANAGER',
]);

const FIELD_ROLES = new Set(['EXECUTIVE', ...MANAGER_ROLES]);

function tenantId(req) {
  return tenant.resolveTenantId(req);
}

function isManager(user) {
  return MANAGER_ROLES.has(user?.role);
}

function isFieldRole(user) {
  return FIELD_ROLES.has(user?.role);
}

function assertFieldAccess(user) {
  if (!isFieldRole(user)) throw Forbidden('Field force access only');
}

function assertManager(user) {
  if (!isManager(user)) throw Forbidden('Manager or admin only');
}

function parsePage(query = {}) {
  const page = Math.max(1, Number.parseInt(query.page, 10) || 1);
  const pageSize = Math.min(100, Math.max(1, Number.parseInt(query.pageSize, 10) || 25));
  return { page, pageSize, skip: (page - 1) * pageSize, take: pageSize };
}

function paginate(items, total, page, pageSize) {
  return { items, total, page, pageSize, pages: Math.ceil(total / pageSize) || 1 };
}

module.exports = {
  MANAGER_ROLES,
  FIELD_ROLES,
  tenantId,
  isManager,
  isFieldRole,
  assertFieldAccess,
  assertManager,
  parsePage,
  paginate,
};
