'use strict';

const http = require('http');
const express = require('express');
const cors = require('cors');
const compression = require('compression');
const morgan = require('morgan');

const config = require('./config');
const logger = require('./utils/logger');
const { notFound, errorHandler } = require('./middleware/errorHandler');
const { baseLimiter } = require('./middleware/rateLimit');
const buildRouter = require('./modules');
const initSockets = require('./sockets');
const startJobs = require('./jobs');
const monitoring = require('./services/monitoring');
const tenant = require('./services/tenant');
const security = require('./middleware/security');
const correlation = require('./middleware/correlationId');
const eventBus = require('./services/eventBus');
const media = require('./services/media');
const email = require('./services/email');
const prisma = require('./database/prisma');
const cache = require('./services/cache');

const app = express();
const server = http.createServer(app);

app.disable('x-powered-by');
app.set('trust proxy', 1);

monitoring.init(app);
app.use(correlation());
app.use(monitoring.metricsMiddleware());
app.use(security.helmet());
app.use(
  cors({
    origin: (origin, cb) => {
      if (!origin) return cb(null, true);
      if (config.cors.webOrigin.includes('*') || config.cors.webOrigin.includes(origin)) return cb(null, true);
      return cb(new Error('CORS blocked'));
    },
    credentials: true,
    exposedHeaders: ['X-Trace-Id'],
  })
);
app.use(compression());
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true, limit: '5mb' }));
app.use(
  morgan(config.env === 'development' ? 'dev' : 'combined', {
    stream: { write: (msg) => logger.info(msg.trim()) },
  })
);

app.use('/api', baseLimiter);
app.use('/api', require('./middleware/responseEnvelope'));

// Liveness vs. readiness: liveness only checks the process is up; readiness
// checks the dependencies the API needs to actually serve requests.
app.get('/health', (_req, res) => res.json({ ok: true, ts: Date.now() }));
app.get('/health/live', (_req, res) => res.json({ ok: true }));
app.get('/health/ready', async (_req, res) => {
  const checks = {
    db: false,
    cache: cache.mode,
    redis: false,
    queue: process.env.QUEUE_DRIVER || 'memory',
    eventTransport: process.env.EVENT_TRANSPORT || 'memory',
    multiTenant: tenant.MULTI_TENANT,
  };
  try { await prisma.$queryRaw`SELECT 1`; checks.db = true; } catch (err) { checks.dbError = err.message; }
  if (cache.redis()) {
    try { checks.redis = (await cache.redis().ping()) === 'PONG'; } catch (err) { checks.redisError = err.message; }
  }
  // DB is the only hard dependency. Redis being down degrades us but doesn't
  // make us un-ready — sockets still work single-instance, queue falls back.
  const ok = checks.db;
  res.status(ok ? 200 : 503).json({ ok, checks, ts: Date.now() });
});
app.get('/api/v1/health', (_req, res) => res.json({ ok: true, ts: Date.now() }));
app.get('/metrics', (_req, res) => {
  res.set('Content-Type', 'text/plain; version=0.0.4');
  res.send(monitoring.renderPrometheus());
});

app.use('/api/v1', require('./middleware/tenantScope').stripClientTenantOverride);
app.use('/api/v1', buildRouter());

monitoring.installErrorHandler(app);
app.use(notFound);
app.use(errorHandler);

const io = initSockets(server);
app.set('io', io);
// Background jobs (cron) reach Socket.IO through global.io since they don't
// have an Express req. Without this, scheduled-task / reminder notifications
// never emit their realtime `notification.created` / `task.assigned` events.
global.io = io;

startJobs();
eventBus.startDispatcher();

// Run media workers in the API process when QUEUE_DRIVER is memory (single
// instance dev / staging). For BullMQ deployments, leave this off and run
// `node src/worker.js` as a separate process.
if (!process.env.QUEUE_DRIVER || process.env.QUEUE_DRIVER === 'memory') {
  media.registerWorker();
  email.registerWorker();
}

tenant.ensureDefaultTenant().catch((err) =>
  logger.warn({ err: err.message }, 'tenant.ensure_default.failed')
);

server.listen(config.port, () => {
  logger.info(
    { port: config.port, env: config.env, multiTenant: tenant.MULTI_TENANT, cache: cache.mode },
    'bestie.api.listening'
  );
});

process.on('unhandledRejection', (reason) => logger.error({ reason }, 'unhandled.rejection'));
process.on('uncaughtException', (err) => logger.error({ err }, 'uncaught.exception'));

module.exports = { app, server, io };
