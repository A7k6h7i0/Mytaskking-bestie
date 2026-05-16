'use strict';

const prisma = require('../database/prisma');
const logger = require('../utils/logger');

/**
 * Central audit logger.
 *
 * Every state-changing action in the platform funnels through here. Writes are
 * fire-and-forget — never block the caller's response on the audit write, but
 * always log the failure so we know if our pipeline drops events.
 *
 * Standard event kinds (snake_case dot-namespaced):
 *   auth.login, auth.logout, auth.refresh, auth.login_failed
 *   employee.created, employee.updated, employee.suspended, employee.deleted
 *   client.created, client.access_extended, client.disabled, client.expired
 *   channel.created, channel.member_added, channel.member_removed, channel.archived
 *   message.deleted, message.edited, message.pinned
 *   task.created, task.assigned, task.status_changed, task.deleted
 *   call.initiated, call.joined, call.ended
 *   telecaller.call_started, telecaller.lead_status_changed
 *   file.uploaded, file.deleted, file.downloaded
 *   settings.changed, announcement.published, permission.changed
 *
 * `entity` + `entityId` describe the affected resource (`task`, `tk_abc`).
 * `payload` is a JSON blob with whatever context is useful for the timeline UI
 * — keep it small (a few hundred bytes); reach into the DB for full details.
 */
async function record({ actorId, kind, entity, entityId, payload, req }) {
  try {
    if (req && !actorId) actorId = req.user?.id;
    const meta = req
      ? { ip: req.ip, ua: req.headers?.['user-agent'] }
      : undefined;
    await prisma.activityLog.create({
      data: {
        actorId: actorId || null,
        kind,
        entity: entity || null,
        entityId: entityId || null,
        payload: payload || meta || null,
      },
    });
    const io = req?.app?.get?.('io');
    io?.emit('activity.recorded', { kind, entity, entityId, actorId, at: Date.now() });
  } catch (err) {
    logger.warn({ err: err.message, kind }, 'audit.write_failed');
  }
}

/**
 * Wrap a route handler so the side-effect is logged automatically.
 * Returns a function with the same signature; if the handler resolves with an
 * object, `entityFn(req, result)` decides what to log.
 */
function audited(kind, entityFn) {
  return (handler) => async (req, res, next) => {
    try {
      const result = await handler(req, res, next);
      try {
        const meta = entityFn ? entityFn(req, result) : {};
        await record({ kind, ...meta, req });
      } catch (auditErr) {
        logger.warn({ err: auditErr.message, kind }, 'audit.wrapper_failed');
      }
      return result;
    } catch (err) {
      next(err);
      return undefined;
    }
  };
}

module.exports = { record, audited };
