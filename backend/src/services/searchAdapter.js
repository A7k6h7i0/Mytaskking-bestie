'use strict';

const logger = require('../utils/logger');

/**
 * Search adapter — the existing `/search` route uses a Postgres-only path that
 * works without any extra infra. For larger workspaces the same surface can
 * route through Meilisearch or Elasticsearch by setting `SEARCH_ENGINE`.
 *
 * Adapter contract (everyone exposes the same shape):
 *
 *   async search({ user, q, kinds, perEntity, recentBoost })
 *     → { results: { [kind]: [item, ...] } }
 *
 *   async index({ entity, id, doc })          // upsert
 *   async deindex({ entity, id })             // remove
 *
 * Modules call `index()` after writes so the external engine stays warm; the
 * default in-process adapter ignores those calls because Postgres is queried
 * live.
 */

const engine = (process.env.SEARCH_ENGINE || 'postgres').toLowerCase();

function loadAdapter() {
  switch (engine) {
    case 'meilisearch':
      // require('./searchAdapters/meilisearch')   // user wires this when ready
      logger.warn('searchAdapter.meilisearch.not_implemented — falling back to postgres');
      return require('./searchAdapters/postgres');
    case 'elasticsearch':
      logger.warn('searchAdapter.elasticsearch.not_implemented — falling back to postgres');
      return require('./searchAdapters/postgres');
    case 'postgres':
    default:
      return require('./searchAdapters/postgres');
  }
}

const adapter = loadAdapter();
logger.info({ engine }, 'searchAdapter.ready');

module.exports = adapter;
