'use strict';

const { verifyAccessToken } = require('../services/tokens');
const prisma = require('../database/prisma');
const { Unauthorized, Forbidden, Gone } = require('../utils/errors');
const tenant = require('../services/tenant');
const monitoring = require('../services/monitoring');

async function requireAuth(req, _res, next) {
  try {
    const header = req.headers.authorization || '';
    const [, token] = header.match(/^Bearer\s+(.+)$/i) || [];
    if (!token) throw Unauthorized('Missing bearer token');

    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch {
      throw Unauthorized('Invalid or expired token');
    }

    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) throw Unauthorized('User no longer exists');
    if (user.status === 'SUSPENDED') throw Forbidden('Account suspended');

    // Enforce client access expiry on every request
    if (user.isClient && user.accessEndsAt && user.accessEndsAt < new Date()) {
      await prisma.user.update({ where: { id: user.id }, data: { status: 'EXPIRED' } }).catch(() => {});
      throw Gone('Client access has expired');
    }

    req.user = user;
    req.tenantId = tenant.MULTI_TENANT ? (user.tenantId || tenant.DEFAULT_TENANT_ID) : null;
    monitoring.setUser(user);
    next();
  } catch (e) {
    next(e);
  }
}

function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.user) return next(Unauthorized());
    if (!roles.includes(req.user.role)) return next(Forbidden('Insufficient role'));
    next();
  };
}

const requireAdmin = requireRole('SUPER_ADMIN', 'ADMIN');
const requireSuperAdmin = requireRole('SUPER_ADMIN');
const requireInternal = requireRole('SUPER_ADMIN', 'ADMIN', 'MANAGER', 'PROJECT_COORDINATOR_MANAGER', 'EXECUTIVE', 'EMPLOYEE', 'TELECALLER');

module.exports = {
  requireAuth,
  requireRole,
  requireAdmin,
  requireSuperAdmin,
  requireInternal,
};
