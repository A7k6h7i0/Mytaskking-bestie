'use strict';

const logger = require('../utils/logger');

/**
 * Thin wrapper around Sentry so the rest of the codebase doesn't need to know
 * whether Sentry is installed/configured. Degrades to no-op if either is
 * missing — useful in dev and CI.
 */
let Sentry = null;
let initialized = false;

function init(app) {
  if (initialized) return;
  initialized = true;

  const dsn = process.env.SENTRY_DSN;
  if (!dsn) {
    logger.info('monitoring.sentry.disabled — set SENTRY_DSN to enable');
    return;
  }
  try {
    Sentry = require('@sentry/node');
    Sentry.init({
      dsn,
      environment: process.env.NODE_ENV || 'development',
      tracesSampleRate: parseFloat(process.env.SENTRY_TRACES_SAMPLE_RATE || '0.1'),
      release: process.env.RELEASE_VERSION || undefined,
    });
    app.use(Sentry.Handlers.requestHandler());
    logger.info('monitoring.sentry.ready');
  } catch (err) {
    logger.warn({ err: err.message }, 'monitoring.sentry.init_failed');
  }
}

function installErrorHandler(app) {
  if (Sentry) app.use(Sentry.Handlers.errorHandler());
}

function captureException(err, ctx) {
  if (Sentry) Sentry.captureException(err, ctx ? { extra: ctx } : undefined);
  else logger.error({ err: err?.message, ctx }, 'monitoring.captured');
}

function setUser(user) {
  if (Sentry && user) Sentry.setUser({ id: user.id, username: user.userId });
}

/**
 * Lightweight in-process metrics — emit Prometheus-shaped lines from a debug
 * endpoint without a heavy `prom-client` dependency. Sufficient for a small
 * fleet; swap out when graduating to a dedicated metrics pipeline.
 */
const metrics = {
  requests: 0,
  requestErrors: 0,
  socketConnections: 0,
  byPath: new Map(),
};

function metricsMiddleware() {
  return (req, res, next) => {
    metrics.requests += 1;
    const start = Date.now();
    res.on('finish', () => {
      if (res.statusCode >= 500) metrics.requestErrors += 1;
      const key = `${req.method} ${req.route?.path || req.path}`;
      const cur = metrics.byPath.get(key) || { count: 0, totalMs: 0 };
      cur.count += 1;
      cur.totalMs += Date.now() - start;
      metrics.byPath.set(key, cur);
    });
    next();
  };
}

function renderPrometheus() {
  const lines = [
    `# HELP bestie_requests_total Total HTTP requests`,
    `# TYPE bestie_requests_total counter`,
    `bestie_requests_total ${metrics.requests}`,
    `# HELP bestie_request_errors_total HTTP responses with status >= 500`,
    `# TYPE bestie_request_errors_total counter`,
    `bestie_request_errors_total ${metrics.requestErrors}`,
    `# HELP bestie_socket_connections Current Socket.IO connections`,
    `# TYPE bestie_socket_connections gauge`,
    `bestie_socket_connections ${metrics.socketConnections}`,
  ];
  for (const [path, v] of metrics.byPath.entries()) {
    const safePath = path.replace(/"/g, '\\"');
    lines.push(`bestie_path_request_total{path="${safePath}"} ${v.count}`);
    lines.push(`bestie_path_request_duration_ms_sum{path="${safePath}"} ${v.totalMs}`);
  }
  return lines.join('\n') + '\n';
}

function trackSocketConnect() { metrics.socketConnections += 1; }
function trackSocketDisconnect() { metrics.socketConnections = Math.max(0, metrics.socketConnections - 1); }

module.exports = {
  init,
  installErrorHandler,
  captureException,
  setUser,
  metricsMiddleware,
  renderPrometheus,
  trackSocketConnect,
  trackSocketDisconnect,
};
