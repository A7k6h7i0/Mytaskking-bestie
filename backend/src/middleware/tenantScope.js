'use strict';

const tenant = require('../services/tenant');

/** Prevent clients from overriding organisation on create/update payloads. */
function stripClientTenantOverride(req, _res, next) {
  if (req.body && typeof req.body === 'object' && !Array.isArray(req.body)) {
    req.body = tenant.stripClientTenantFields(req.body);
  }
  next();
}

module.exports = { stripClientTenantOverride };
