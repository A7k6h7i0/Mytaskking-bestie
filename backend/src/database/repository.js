'use strict';

const { PrismaClient } = require('@prisma/client');
const logger = require('../utils/logger');
const cache = require('../services/cache');

/**
 * Repository wrapper around Prisma.
 *
 * Why this exists:
 *   1. Read-replica routing. When `READ_REPLICA_URL` is set, read-only
 *      queries (`findUnique`, `findMany`, `count`, aggregates) prefer the
 *      replica client. Writes always go to the primary. Modules ask for
 *      `repo.reader.*` vs `repo.writer.*` instead of `prisma.*`.
 *   2. Transaction-safe services. `repo.tx(async (rw) => …)` opens a
 *      transaction on the writer. Inside the callback, you get a tx-bound
 *      client whose reads land in the same transaction.
 *   3. Cached lookups. `repo.cachedFindUnique(model, key, ttl)` memoizes
 *      hot-path single-row reads through the cache service.
 *
 * Existing modules still import `database/prisma` directly — both paths work.
 * Migrate the hot-read paths first (`User.findUnique` in auth middleware,
 * `Channel.findMany` in the chat list).
 */

const writer = require('./prisma');
let reader;
const REPLICA_URL = process.env.READ_REPLICA_URL;

if (REPLICA_URL) {
  reader = new PrismaClient({ datasources: { db: { url: REPLICA_URL } } });
  logger.info('repository.read_replica.ready');
} else {
  reader = writer;
}

async function tx(fn) {
  return writer.$transaction(async (txClient) => fn(txClient));
}

function cachedFindUnique(model, where, { ttl = 30, keyFn } = {}) {
  const ck = keyFn ? keyFn(where) : `repo:${model}:${stableKey(where)}`;
  return cache.memoize(() => ck, async () => reader[model].findUnique({ where }), ttl)();
}

function stableKey(obj) {
  return Object.keys(obj).sort().map((k) => `${k}=${obj[k]}`).join(';');
}

module.exports = {
  reader,
  writer,
  tx,
  cachedFindUnique,
};
