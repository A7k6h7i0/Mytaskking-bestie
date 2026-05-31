'use strict';

const { EventEmitter } = require('events');
const prisma = require('../database/prisma');
const logger = require('../utils/logger');

/**
 * Internal event bus — modules emit domain events here and never call each
 * other directly. Today the implementation is an in-process EventEmitter
 * with a database-backed outbox for durability. The dispatcher reads the
 * outbox and forwards events to the configured transport (Kafka / RabbitMQ
 * / SQS). Wiring a new transport doesn't touch the call sites.
 *
 * Naming: dot-namespaced topic strings, matching audit kinds where it makes
 * sense — `task.created`, `message.created`, `call.initiated`, …
 *
 *   eventBus.publish('task.created', payload, { tx })
 *   eventBus.subscribe('task.*', async (event) => { … })
 *
 * Subscribers always run async; errors are swallowed and logged so a single
 * bad handler can't take down the producer.
 */

const TRANSPORT = (process.env.EVENT_TRANSPORT || 'memory').toLowerCase();
const ee = new EventEmitter();
ee.setMaxListeners(200);

function matchesPattern(pattern, topic) {
  if (pattern === topic || pattern === '*') return true;
  if (pattern.endsWith('.*')) return topic.startsWith(pattern.slice(0, -1));
  return false;
}

const patternHandlers = []; // [{pattern, handler}]

ee.on('error', (err) => logger.warn({ err: err.message }, 'eventBus.handler_error'));

function subscribe(pattern, handler) {
  const wrapped = async (event) => {
    try { await handler(event); }
    catch (err) { logger.warn({ err: err.message, topic: event.topic }, 'eventBus.handler_failed'); }
  };
  patternHandlers.push({ pattern, handler: wrapped });
  return () => {
    const idx = patternHandlers.findIndex((h) => h.handler === wrapped);
    if (idx >= 0) patternHandlers.splice(idx, 1);
  };
}

function emitInternal(event) {
  for (const { pattern, handler } of patternHandlers) {
    if (matchesPattern(pattern, event.topic)) {
      Promise.resolve().then(() => handler(event));
    }
  }
}

/**
 * Publish a domain event. Set `tx` to the current Prisma transaction client
 * to make the outbox write part of the same atomic step as your state change.
 *
 *   await prisma.$transaction(async (tx) => {
 *     await tx.task.create(...);
 *     await eventBus.publish('task.created', { id }, { tx });
 *   });
 */
async function publish(topic, payload, { tx, tenantId, durable = true } = {}) {
  const event = { topic, payload, tenantId: tenantId ?? null, at: Date.now() };
  if (durable) {
    try {
      await (tx || prisma).outboxEvent.create({
        data: { topic, payload, tenantId: event.tenantId },
      });
    } catch (err) {
      logger.warn({ err: err.message, topic }, 'eventBus.outbox_write_failed');
    }
  }
  emitInternal(event);
  return event;
}

/**
 * Outbox dispatcher — picks up pending rows and forwards to the external
 * transport (or, today, just marks them dispatched since the in-process
 * fanout already happened). Runs every 2 seconds; idempotent.
 */
let dispatcherTimer = null;
function startDispatcher({ batchSize = 50, intervalMs = 2_000 } = {}) {
  if (dispatcherTimer) return;
  dispatcherTimer = setInterval(async () => {
    try {
      const pending = await prisma.outboxEvent.findMany({
        where: { status: 'PENDING' },
        orderBy: { createdAt: 'asc' },
        take: batchSize,
      });
      for (const row of pending) {
        try {
          await transportSend(row);
          await prisma.outboxEvent.update({
            where: { id: row.id },
            data: { status: 'DISPATCHED', dispatchedAt: new Date(), attempts: { increment: 1 } },
          });
        } catch (err) {
          await prisma.outboxEvent.update({
            where: { id: row.id },
            data: { attempts: { increment: 1 }, lastError: err.message, status: row.attempts >= 9 ? 'FAILED' : 'PENDING' },
          });
        }
      }
    } catch (err) {
      logger.warn({ err: err.message }, 'eventBus.dispatcher_tick_failed');
    }
  }, intervalMs).unref?.();
  logger.info({ transport: TRANSPORT, intervalMs }, 'eventBus.dispatcher.started');
}

async function transportSend(_row) {
  switch (TRANSPORT) {
    case 'kafka':
    case 'rabbitmq':
    case 'sqs':
      // Adapter implementations live in services/eventTransports/<name>.js when wired.
      throw new Error(`event transport ${TRANSPORT} not implemented — falling back to memory`);
    case 'memory':
    default:
      // In-process fanout already happened at publish() time.
      return;
  }
}

module.exports = { publish, subscribe, startDispatcher };
