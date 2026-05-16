'use strict';

/**
 * Standalone worker process.
 *
 * Runs the same code as the API but exits without binding any HTTP port; the
 * job is to drain BullMQ queues (media, notifications, automations, search-
 * indexer) at scale. PM2 / Kubernetes runs N workers; the API process runs
 * with QUEUE_DRIVER=memory or the worker registration disabled.
 *
 *   node src/worker.js
 *
 * The worker shares the same Prisma client, cache service, and queue driver
 * as the API, so there's no separate config story.
 */

require('dotenv').config();

const logger = require('./utils/logger');
const media = require('./services/media');
const email = require('./services/email');
const eventBus = require('./services/eventBus');

media.registerWorker();
email.registerWorker();
eventBus.startDispatcher();

logger.info({ pid: process.pid }, 'bestie.worker.ready');

process.on('SIGTERM', () => {
  logger.info('worker.sigterm — draining queues');
  setTimeout(() => process.exit(0), 5_000).unref();
});

process.on('unhandledRejection', (reason) => logger.error({ reason }, 'worker.unhandled_rejection'));
process.on('uncaughtException', (err) => logger.error({ err: err.message }, 'worker.uncaught_exception'));
