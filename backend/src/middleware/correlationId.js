'use strict';

const crypto = require('crypto');
const { AsyncLocalStorage } = require('async_hooks');

/**
 * Per-request correlation IDs.
 *
 * • Honors `X-Trace-Id` from upstream if present (e.g. set by Cloudflare or an
 *   API gateway). Otherwise mints a random 16-char id.
 * • Stores `{ traceId, userId, tenantId }` in AsyncLocalStorage so logs deep
 *   inside services can pick it up without threading the request object
 *   through every call.
 * • Echoes the id back on the response and into the structured logger.
 *
 * This is the bedrock for the future OpenTelemetry integration — when you
 * swap in OTel, replace the random id with `trace.getActiveSpan()?.spanContext()`
 * and the ALS bindings carry through unchanged.
 */

const als = new AsyncLocalStorage();

function correlationId() {
  return als.getStore()?.traceId || null;
}

function currentContext() {
  return als.getStore() || {};
}

module.exports = function correlationMiddleware() {
  return (req, res, next) => {
    const incoming = req.headers['x-trace-id'];
    const traceId = (incoming && /^[A-Za-z0-9_-]{6,64}$/.test(incoming))
      ? incoming
      : crypto.randomBytes(8).toString('hex');
    res.set('X-Trace-Id', traceId);
    req.traceId = traceId;
    als.run({ traceId, userId: null, tenantId: null }, () => next());
  };
};

module.exports.correlationId = correlationId;
module.exports.currentContext = currentContext;
module.exports.bindUser = function bindUser(user) {
  const store = als.getStore();
  if (!store || !user) return;
  store.userId = user.id;
  store.tenantId = user.tenantId || null;
};
