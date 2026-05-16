'use strict';

const queue = require('./queue');
const logger = require('../utils/logger');

/**
 * Email delivery — fire jobs onto the queue, let a worker drain them. Same
 * adapter pattern as the rest of the platform: provider-agnostic, ships with
 * a noop sender, ready to swap in SendGrid / SES / Postmark / Resend without
 * touching call sites.
 *
 *   email.send({
 *     to: 'priya@example.com',
 *     subject: 'You were added to #onboarding',
 *     html: '...',
 *     text: '...',
 *     tags: ['channel.invite'],
 *   });
 *
 * The provider is selected by `EMAIL_PROVIDER=noop|sendgrid|ses|postmark|resend`.
 * Today only `noop` is wired — it logs the would-be send and resolves cleanly,
 * which is exactly what dev environments want.
 */

const PROVIDER = (process.env.EMAIL_PROVIDER || 'noop').toLowerCase();
const FROM = process.env.EMAIL_FROM || 'no-reply@bestie.app';

async function send(payload) {
  // Validate at enqueue time so bad calls fail loudly instead of silently piling
  // up in the queue.
  if (!payload.to || (!payload.html && !payload.text)) {
    throw new Error('email.send: `to` and one of `html`/`text` are required');
  }
  return queue.enqueue('email', payload, { attempts: 5 });
}

async function dispatch(job) {
  const data = job.data;
  switch (PROVIDER) {
    case 'sendgrid':
    case 'ses':
    case 'postmark':
    case 'resend':
      // Adapter implementations live in services/emailProviders/<name>.js when wired.
      throw new Error(`email provider ${PROVIDER} not implemented — falling back to noop`);
    case 'noop':
    default:
      logger.info(
        { to: data.to, subject: data.subject, tags: data.tags || [], from: FROM },
        'email.noop.send'
      );
      return { ok: true, provider: 'noop' };
  }
}

function registerWorker() {
  queue.process('email', dispatch);
  logger.info({ provider: PROVIDER }, 'email.worker.registered');
}

module.exports = { send, dispatch, registerWorker };
