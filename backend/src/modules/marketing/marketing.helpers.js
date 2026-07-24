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

function isExecutive(user) {
  return user?.role === 'EXECUTIVE';
}

/** Visits, orders, and live GPS pings are field-executive actions only. */
function assertExecutiveFieldWorker(user) {
  if (!isExecutive(user)) {
    throw Forbidden('Field visits and orders are for executives only');
  }
}

/** Managers cannot approve or resolve their own submissions. */
function assertNotOwnSubmission(req, row, field = 'userId') {
  const submitterId = row?.[field];
  if (submitterId && submitterId === req.user.id) {
    throw Forbidden('Cannot act on your own submission');
  }
}

/** Executive may view outlets they created or are assigned to (if approved). */
function assertExecutiveOutletRead(user, outlet) {
  if (isManager(user)) return;
  const ok =
    outlet.createdById === user.id ||
    (outlet.assignedToId === user.id && outlet.approvalStatus === 'approved');
  if (!ok) throw Forbidden('Not authorized for this outlet');
}

/** Executive field actions (visit, order) require an approved outlet assigned to them. */
function assertExecutiveOutletTransact(user, outlet) {
  if (isManager(user)) return;
  if (outlet.approvalStatus !== 'approved') {
    throw Forbidden('Outlet is pending manager approval');
  }
  if (outlet.assignedToId !== user.id) {
    throw Forbidden('Outlet is not assigned to you');
  }
}

/** Prisma where-clause for executive-visible outlets (matches listOutlets). */
function executiveOutletWhere(user) {
  return {
    OR: [
      { createdById: user.id },
      {
        AND: [{ assignedToId: user.id }, { approvalStatus: 'approved' }],
      },
    ],
  };
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
  isExecutive,
  isFieldRole,
  assertFieldAccess,
  assertManager,
  assertExecutiveFieldWorker,
  assertNotOwnSubmission,
  assertExecutiveOutletRead,
  assertExecutiveOutletTransact,
  executiveOutletWhere,
  parsePage,
  paginate,
};
