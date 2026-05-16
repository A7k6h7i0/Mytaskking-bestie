'use strict';

/**
 * Standardized response envelope.
 *
 * Existing routes return data directly for backwards compatibility. New routes
 * (and migrated ones) can opt in by attaching `res.locals.envelope = true`
 * before sending, and using `res.success(data)` / `res.fail(code, message)`.
 *
 * Shape:
 *   { ok: true, data: <payload>, meta?: <pagination>, traceId? }
 *   { ok: false, error: { code, message, details?, traceId? } }
 *
 * The legacy error handler is already in this shape under `error`, so the only
 * "new" surface here is the success path.
 */
const crypto = require('crypto');

module.exports = function responseEnvelope(req, res, next) {
  const traceId = req.headers['x-trace-id'] || crypto.randomBytes(8).toString('hex');
  res.set('X-Trace-Id', traceId);

  res.success = (data, meta) => res.json({ ok: true, data, ...(meta ? { meta } : {}), traceId });
  res.fail = (status, code, message, details) => res.status(status).json({ ok: false, error: { code, message, details, traceId } });

  next();
};
