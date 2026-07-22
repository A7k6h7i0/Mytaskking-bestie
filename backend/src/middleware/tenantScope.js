'use strict';

const tenant = require('../services/tenant');

/** Prevent clients from overriding organisation on create/update payloads. */
function stripClientTenantOverride(req, _res, next) {
  const p = req.path || '';
  if (
    p.startsWith('/auth/') || p.startsWith('auth/') ||
    p.startsWith('/billing/') || p.startsWith('billing/') ||
    p.startsWith('/tenants/register') || p.startsWith('tenants/register')
  ) {
    return next();
  }
  if (req.body && typeof req.body === 'object' && !Array.isArray(req.body)) {
    req.body = tenant.stripClientTenantFields(req.body);
  }
  next();
}

module.exports = { stripClientTenantOverride };
