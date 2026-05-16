'use strict';

const pino = require('pino');
const config = require('../config');
const { currentContext } = require('../middleware/correlationId');

const logger = pino({
  level: config.logLevel,
  // Pull trace + user context into every log line without callers having to
  // pass it explicitly. Lazy-required to avoid a circular import at boot.
  mixin: () => {
    try {
      const ctx = currentContext();
      return ctx?.traceId ? { traceId: ctx.traceId, userId: ctx.userId, tenantId: ctx.tenantId } : {};
    } catch {
      return {};
    }
  },
  transport:
    config.env === 'development'
      ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:HH:MM:ss' } }
      : undefined,
});

module.exports = logger;
