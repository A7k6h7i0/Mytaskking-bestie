'use strict';

const logger = require('../utils/logger');
const config = require('../config');

/**
 * Cache + shared in-memory primitives.
 *
 * If `REDIS_URL` is set, uses ioredis under the hood (session cache, rate
 * limit storage, presence, Socket.IO clustering, BullMQ queues all share
 * this connection). If not, transparently falls back to an in-memory Map
 * with TTL — fine for dev and small single-instance deployments.
 *
 *   const cache = require('./services/cache');
 *   await cache.set('user:profile:abc', user, 60);
 *   const u = await cache.get('user:profile:abc');
 *   const client = cache.redis();   // raw ioredis or null
 */

let redis = null;
let mode = 'memory';

if (config.redis.url) {
  try {
    const Redis = require('ioredis');
    redis = new Redis(config.redis.url, {
      maxRetriesPerRequest: 2,
      lazyConnect: false,
      enableReadyCheck: true,
      // Cap retries — without this, ioredis keeps trying forever and the
      // logs fill up while in-memory mode silently works.
      retryStrategy: (times) => (times > 5 ? null : Math.min(times * 200, 2000)),
      reconnectOnError: () => false,
    });

    // Suppress the reconnect-storm: log the first error, then fall back to
    // memory mode if Redis stays down. The cache API keeps working — it just
    // routes through the in-process Map.
    let errorsLogged = 0;
    redis.on('error', (err) => {
      if (errorsLogged === 0) {
        logger.warn({ err: err.message }, 'cache.redis.error (further errors suppressed)');
      }
      errorsLogged += 1;
    });
    redis.on('end', () => {
      if (mode === 'redis') {
        logger.warn('cache.redis.disconnected — falling back to memory');
        mode = 'memory';
        try { redis.disconnect(); } catch {}
        redis = null;
      }
    });
    redis.on('ready', () => {
      mode = 'redis';
      logger.info('cache.redis.ready');
    });
  } catch (err) {
    logger.warn({ err: err.message }, 'cache.redis.unavailable — falling back to memory');
    redis = null;
    mode = 'memory';
  }
}

const mem = new Map();      // key -> { value, exp }
const memTimers = new Map();

function nowSec() { return Math.floor(Date.now() / 1000); }

async function get(key) {
  if (redis) {
    const raw = await redis.get(key).catch(() => null);
    return raw == null ? null : safeParse(raw);
  }
  const row = mem.get(key);
  if (!row) return null;
  if (row.exp && row.exp < nowSec()) { mem.delete(key); return null; }
  return row.value;
}

async function set(key, value, ttlSeconds = 0) {
  if (redis) {
    const payload = JSON.stringify(value);
    if (ttlSeconds > 0) await redis.set(key, payload, 'EX', ttlSeconds);
    else await redis.set(key, payload);
    return;
  }
  mem.set(key, { value, exp: ttlSeconds ? nowSec() + ttlSeconds : 0 });
  if (ttlSeconds) {
    clearTimeout(memTimers.get(key));
    memTimers.set(key, setTimeout(() => mem.delete(key), ttlSeconds * 1000).unref?.());
  }
}

async function del(key) {
  if (redis) return redis.del(key).catch(() => 0);
  mem.delete(key);
}

async function incr(key, ttlSeconds = 0) {
  if (redis) {
    const n = await redis.incr(key);
    if (ttlSeconds && n === 1) await redis.expire(key, ttlSeconds);
    return n;
  }
  const row = mem.get(key);
  const next = (row?.value || 0) + 1;
  await set(key, next, ttlSeconds);
  return next;
}

function safeParse(raw) {
  try { return JSON.parse(raw); } catch { return raw; }
}

/** Cache wrapper for any pure async function. */
function memoize(keyFn, fn, ttlSeconds = 60) {
  return async (...args) => {
    const key = keyFn(...args);
    const cached = await get(key);
    if (cached != null) return cached;
    const fresh = await fn(...args);
    await set(key, fresh, ttlSeconds);
    return fresh;
  };
}

module.exports = {
  get mode() {
    return mode;
  },
  redis: () => redis,
  get, set, del, incr, memoize,
};
