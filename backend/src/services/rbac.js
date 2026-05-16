'use strict';

const prisma = require('../database/prisma');
const logger = require('../utils/logger');

/**
 * Advanced RBAC — sits on top of the legacy `Role` enum without replacing it.
 *
 * Permission keys are dot-namespaced strings. They're free-form so a new
 * module can introduce keys without a schema migration. Examples:
 *
 *   module:    "audit.view", "telecaller.access"
 *   action:    "task.delete", "task.assign_others"
 *   channel:   "channel.manage", "channel.invite", "channel.delete"
 *   file:      "file.upload", "file.view_client", "file.share_external"
 *   call:      "call.record", "call.transfer"
 *
 * Resolution order (first match wins):
 *   1) explicit deny grant on the user
 *   2) explicit allow grant on the user
 *   3) deny grant on the user's role
 *   4) allow grant on the user's role
 *   5) baked-in role defaults (DEFAULT_MATRIX)
 *
 * The bundled defaults preserve the legacy role behavior so existing routes
 * stay correct even before anyone configures grants.
 */

const DEFAULT_MATRIX = {
  SUPER_ADMIN: ['*'],
  ADMIN: [
    'employee.*', 'client.*',
    'channel.*', 'message.*', 'task.*',
    'call.*', 'telecaller.*',
    'file.*',
    'audit.view', 'analytics.view', 'announcement.publish',
    'settings.write', 'session.force_logout',
    'permission.write',
  ],
  EMPLOYEE: [
    'channel.read', 'channel.post', 'channel.invite',
    'message.*', 'task.read', 'task.create', 'task.update', 'task.assign_self',
    'call.read', 'call.create',
    'file.upload', 'file.read',
    'calendar.*',
  ],
  TELECALLER: [
    'telecaller.access', 'telecaller.call', 'telecaller.lead_manage',
    'channel.read', 'channel.post', 'message.read', 'message.create',
    'call.read', 'call.create',
    'calendar.read',
  ],
  CLIENT: [
    'channel.read', 'message.read', 'message.create',
    'file.read',
    'calendar.read',
  ],
};

function matches(pattern, key) {
  if (pattern === '*' || pattern === key) return true;
  if (pattern.endsWith('.*')) {
    const prefix = pattern.slice(0, -1); // includes the dot
    return key.startsWith(prefix);
  }
  return false;
}

function defaultAllowed(role, key) {
  const patterns = DEFAULT_MATRIX[role] || [];
  return patterns.some((p) => matches(p, key));
}

/**
 * Returns `true` if the user is allowed to perform `key`.
 *
 *   const allowed = await can(user, 'task.delete', { taskId: id });
 *
 * `scope` is currently advisory — grants can carry a JSON scope that callers
 * compare in their own logic (e.g. `grant.scope.channelId === channelId`).
 */
async function can(user, key, scope) {
  if (!user) return false;

  try {
    const grants = await prisma.permissionGrant.findMany({
      where: {
        OR: [{ userId: user.id }, { roleName: user.role }],
        key,
      },
    });

    // 1) user deny
    if (grants.some((g) => g.userId === user.id && g.allow === false && scopeMatches(g.scope, scope))) return false;
    // 2) user allow
    if (grants.some((g) => g.userId === user.id && g.allow && scopeMatches(g.scope, scope))) return true;
    // 3) role deny
    if (grants.some((g) => g.roleName === user.role && g.allow === false && scopeMatches(g.scope, scope))) return false;
    // 4) role allow
    if (grants.some((g) => g.roleName === user.role && g.allow && scopeMatches(g.scope, scope))) return true;
  } catch (err) {
    logger.warn({ err: err.message }, 'rbac.grant_lookup_failed');
  }

  // 5) defaults
  return defaultAllowed(user.role, key);
}

function scopeMatches(grantScope, askedScope) {
  if (!grantScope) return true;
  if (!askedScope) return false;
  return Object.entries(grantScope).every(([k, v]) => askedScope[k] === v);
}

/** Express middleware shorthand: `router.post('/x', requirePerm('task.delete'), handler)` */
function requirePerm(key, scopeFn) {
  return async (req, _res, next) => {
    if (!req.user) return next({ status: 401, code: 'unauthorized', message: 'Unauthorized' });
    const scope = scopeFn ? scopeFn(req) : undefined;
    const allowed = await can(req.user, key, scope);
    if (!allowed) {
      const err = new Error('Insufficient permissions'); err.status = 403; err.code = 'forbidden';
      return next(err);
    }
    next();
  };
}

async function listEffective(user) {
  // Useful for the frontend to hide/show buttons.
  const explicit = await prisma.permissionGrant.findMany({
    where: { OR: [{ userId: user.id }, { roleName: user.role }] },
  });
  return {
    role: user.role,
    defaults: DEFAULT_MATRIX[user.role] || [],
    grants: explicit,
  };
}

module.exports = { can, requirePerm, listEffective, DEFAULT_MATRIX };
