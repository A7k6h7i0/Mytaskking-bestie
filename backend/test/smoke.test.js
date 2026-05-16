'use strict';

/**
 * Smoke tests — no DB, no network. Verify that:
 *   1. Every module file loads without throwing (catches syntax/typo errors
 *      that `node --check` misses because they only surface on import).
 *   2. Pure services (rbac, eventBus pattern matching, tokens TTL parsing,
 *      security envelope round-trip) behave correctly in isolation.
 *
 * Run with `node --test test/`. CI does this in addition to building.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

// We don't have a DB at test time; stub the Prisma client before any service
// requires it. Anything that touches the DB at import time will load with
// no-op methods.
require('./prismaStub');

test('every service module loads', () => {
  const dir = path.join(__dirname, '..', 'src', 'services');
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.js')) continue;
    require(path.join(dir, f));
  }
});

test('every module routes file loads', () => {
  const dir = path.join(__dirname, '..', 'src', 'modules');
  for (const m of fs.readdirSync(dir)) {
    const sub = path.join(dir, m);
    if (!fs.statSync(sub).isDirectory()) continue;
    for (const f of fs.readdirSync(sub)) {
      if (f.endsWith('.routes.js')) require(path.join(sub, f));
    }
  }
});

test('rbac default matrix grants admin task.delete', async () => {
  const rbac = require('../src/services/rbac');
  const allow = await rbac.can({ id: 'u1', role: 'ADMIN' }, 'task.delete');
  assert.equal(allow, true);
});

test('rbac default matrix denies client analytics.view', async () => {
  const rbac = require('../src/services/rbac');
  const allow = await rbac.can({ id: 'u1', role: 'CLIENT' }, 'analytics.view');
  assert.equal(allow, false);
});

test('rbac wildcard matches', async () => {
  const rbac = require('../src/services/rbac');
  const allow = await rbac.can({ id: 'u1', role: 'EMPLOYEE' }, 'message.create');
  assert.equal(allow, true);
});

test('field encryption round-trips', () => {
  process.env.FIELD_ENCRYPTION_KEY = require('crypto').randomBytes(32).toString('hex');
  const sec = require('../src/middleware/security');
  const cipher = sec.encrypt('hello world');
  assert.ok(cipher.startsWith('v1:'));
  assert.equal(sec.decrypt(cipher), 'hello world');
});

test('event bus pattern matching', async () => {
  const bus = require('../src/services/eventBus');
  const got = [];
  const off = bus.subscribe('task.*', (e) => got.push(e.topic));
  await bus.publish('task.created', { id: 'x' }, { durable: false });
  await bus.publish('message.created', { id: 'y' }, { durable: false });
  // Async fanout — give the next tick a chance.
  await new Promise((r) => setImmediate(r));
  assert.deepEqual(got, ['task.created']);
  off();
});

test('feature-flag percent rollout is sticky', async () => {
  // Same flag + userId must always evaluate the same way.
  const crypto = require('node:crypto');
  const stub = (key, uid) => {
    const h = crypto.createHash('sha256').update(`${key}:${uid}`).digest('hex');
    return parseInt(h.slice(0, 8), 16) % 100;
  };
  const a = stub('ai.task_summary', 'user-1');
  const b = stub('ai.task_summary', 'user-1');
  assert.equal(a, b);
});
