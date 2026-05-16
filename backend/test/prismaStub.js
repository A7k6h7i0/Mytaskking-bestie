'use strict';

/**
 * Stub the Prisma client at module-resolution time so services that require
 * `database/prisma` at import don't try to open a connection. We replace the
 * module with a Proxy that returns no-op-ish methods for any model / query.
 *
 * This is enough for smoke tests that only exercise pure functions. Real
 * integration tests should boot a Postgres fixture (the CI workflow does
 * exactly that) and use the actual client.
 */

const Module = require('node:module');
const path = require('node:path');

const PRISMA_PATH = path.join(__dirname, '..', 'src', 'database', 'prisma.js');

const noop = () => Promise.resolve(null);
const stubClient = new Proxy({}, {
  get(_target, prop) {
    // Common Prisma top-level methods.
    if (prop === '$transaction') return (arr) => Array.isArray(arr) ? Promise.resolve([]) : arr({});
    if (prop === '$queryRaw') return noop;
    if (prop === '$disconnect' || prop === '$on') return () => {};
    // Per-model stubs: every model becomes another proxy with no-op methods.
    return new Proxy({}, {
      get(_t, method) {
        if (method === 'findUnique' || method === 'findFirst') return noop;
        if (method === 'findMany') return () => Promise.resolve([]);
        if (method === 'count' || method === 'aggregate') return () => Promise.resolve(0);
        if (method === 'groupBy') return () => Promise.resolve([]);
        if (method === 'create' || method === 'update' || method === 'upsert') return noop;
        if (method === 'delete') return noop;
        if (method === 'updateMany' || method === 'deleteMany' || method === 'createMany') return () => Promise.resolve({ count: 0 });
        return noop;
      },
    });
  },
});

require.cache[PRISMA_PATH] = {
  id: PRISMA_PATH,
  filename: PRISMA_PATH,
  loaded: true,
  exports: stubClient,
};
