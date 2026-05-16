'use strict';

const logger = require('../utils/logger');
const cache = require('./cache');

/**
 * Background job queue.
 *
 * • If Redis is configured AND `QUEUE_DRIVER=bullmq`, this is a thin wrapper
 *   around BullMQ — handles retry/backoff, dead-letter queues, worker scaling,
 *   metrics.
 * • Otherwise (dev, single-instance prod), an in-process driver runs jobs in
 *   a setImmediate loop with the same API. No durability across restarts.
 *
 *   queue.enqueue('media.compress', { fileId }, { attempts: 5 });
 *   queue.process('media.compress', async (job) => { … });
 *
 * Callers shouldn't care which driver they're talking to — both honor the
 * same contract.
 */

const DRIVER = (process.env.QUEUE_DRIVER || (cache.redis() ? 'bullmq' : 'memory')).toLowerCase();

let bullmq = null;
const queues = new Map();   // name → BullMQ Queue or memory state

function loadBullmq() {
  if (bullmq) return bullmq;
  try {
    bullmq = require('bullmq');
    return bullmq;
  } catch (err) {
    logger.warn({ err: err.message }, 'queue.bullmq.unavailable — falling back to memory');
    return null;
  }
}

function getOrCreateQueue(name) {
  if (queues.has(name)) return queues.get(name);

  if (DRIVER === 'bullmq') {
    const lib = loadBullmq();
    if (lib) {
      const q = new lib.Queue(name, { connection: cache.redis() });
      queues.set(name, { driver: 'bullmq', queue: q, handler: null });
      return queues.get(name);
    }
  }

  const state = { driver: 'memory', pending: [], handler: null, processing: false };
  queues.set(name, state);
  return state;
}

async function enqueue(name, data, { delayMs = 0, attempts = 3, jobId } = {}) {
  const q = getOrCreateQueue(name);
  if (q.driver === 'bullmq') {
    return q.queue.add(name, data, { delay: delayMs, attempts, jobId, removeOnComplete: 1000, removeOnFail: 5000, backoff: { type: 'exponential', delay: 2_000 } });
  }
  const job = { id: jobId || `${name}:${Date.now()}:${Math.random()}`, data, attempts, attempt: 0 };
  if (delayMs > 0) setTimeout(() => pushMem(q, job), delayMs).unref?.();
  else pushMem(q, job);
  return job;
}

function pushMem(q, job) {
  q.pending.push(job);
  drainMem(q);
}

async function drainMem(q) {
  if (q.processing || !q.handler) return;
  q.processing = true;
  try {
    while (q.pending.length > 0) {
      const job = q.pending.shift();
      try {
        await q.handler(job);
      } catch (err) {
        job.attempt += 1;
        if (job.attempt < job.attempts) {
          setTimeout(() => pushMem(q, job), 1000 * Math.pow(2, job.attempt)).unref?.();
        } else {
          logger.warn({ err: err.message, jobId: job.id }, 'queue.job.failed_permanently');
        }
      }
    }
  } finally {
    q.processing = false;
  }
}

// NOTE: do not rename this function back to `process` — a hoisted function
// declaration named `process` shadows the global Node.js `process` object
// module-wide, which breaks every `process.env.*` read earlier in this file
// (including line 22 where DRIVER is resolved).
function register(name, handler) {
  const q = getOrCreateQueue(name);
  if (q.driver === 'bullmq') {
    const lib = loadBullmq();
    new lib.Worker(name, handler, { connection: cache.redis(), concurrency: 4 });
    logger.info({ name }, 'queue.bullmq.worker_started');
  } else {
    q.handler = handler;
    drainMem(q);
    logger.info({ name }, 'queue.memory.handler_registered');
  }
}

// Export under both names so existing `queue.process(...)` callers keep working.
module.exports = { driver: DRIVER, enqueue, register, process: register };
