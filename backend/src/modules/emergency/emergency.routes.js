'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const fcm = require('../../services/fcm');
const notificationActions = require('../../services/notificationActions');
const audit = require('../../services/audit');

const router = Router();
router.use(requireAuth);

// In-memory escalation timers, keyed by alertId. Emergency alerts are
// short-lived (seconds), so in-process state is acceptable; on restart any
// in-flight escalation simply won't fire (the admin can re-trigger).
const pending = new Map();

async function sendEmergencyPush(io, { targetId, alertId, fromName, message, escalation }) {
  io?.to(`user:${targetId}`).emit('emergency.alert', {
    alertId,
    fromName,
    message,
    escalation: !!escalation,
  });
  const devices = await prisma.deviceToken.findMany({ where: { userId: targetId } });
  if (!devices.length) return;
  await fcm
    .sendToTokens(devices.map((d) => d.token), {
      title: escalation ? '🚨 URGENT: response required' : '🚨 Emergency alert',
      body: message || `${fromName} needs your immediate attention`,
      data: {
        type: 'emergency.alert',
        alertId,
        fromName,
        message: message || '',
        escalation: escalation ? '1' : '0',
        apiBaseUrl: notificationActions.publicApiBaseUrl(),
      },
    })
    .catch(() => {});
}

// Admin triggers an emergency siren to one or more employees.
router.post(
  '/alert',
  requireAdmin,
  validate({
    body: Joi.object({
      userId: Joi.string(),
      userIds: Joi.array().items(Joi.string()).min(1),
      message: Joi.string().max(280).allow('', null),
      // Seconds to wait for an ack before escalating to the user's supervisors.
      escalateAfter: Joi.number().integer().min(15).max(600).default(60),
    }).or('userId', 'userIds'),
  }),
  asyncHandler(async (req, res) => {
    const io = req.app.get('io');
    const targets = Array.from(
      new Set([
        ...(req.body.userId ? [req.body.userId] : []),
        ...((Array.isArray(req.body.userIds) ? req.body.userIds : [])),
      ])
    );
    const message = (req.body.message || '').trim();
    const fromName = req.user.name;
    const alerts = [];

    for (const targetId of targets) {
      const log = await prisma.activityLog.create({
        data: {
          actorId: req.user.id,
          kind: 'emergency.alert',
          entity: 'user',
          entityId: targetId,
          payload: { message, escalateAfter: req.body.escalateAfter, acked: false },
        },
      });
      alerts.push({ alertId: log.id, targetId });
      await sendEmergencyPush(io, { targetId, alertId: log.id, fromName, message });

      // Escalation: if not acked in `escalateAfter`s, re-alert + notify the
      // target's supervisors so the situation is escalated.
      const timer = setTimeout(async () => {
        pending.delete(log.id);
        try {
          const cur = await prisma.activityLog.findUnique({ where: { id: log.id } });
          if (!cur || cur.payload?.acked) return; // already acknowledged
          // Re-blast the original target.
          await sendEmergencyPush(io, { targetId, alertId: log.id, fromName, message, escalation: true });
          // Notify supervisors.
          const sups = await prisma.userSupervisor.findMany({
            where: { userId: targetId },
            select: { supervisorId: true },
          });
          const target = await prisma.user.findUnique({
            where: { id: targetId },
            select: { name: true },
          });
          for (const s of sups) {
            await sendEmergencyPush(io, {
              targetId: s.supervisorId,
              alertId: log.id,
              fromName,
              message: `${target?.name || 'A team member'} hasn't responded to an emergency alert`,
              escalation: true,
            });
          }
        } catch (_) {/* best-effort escalation */}
      }, req.body.escalateAfter * 1000);
      pending.set(log.id, timer);
    }

    audit.record({ kind: 'emergency.triggered', entity: 'user', payload: { targets, message }, req });
    res.status(201).json({ alerts });
  })
);

// Recipient acknowledges ("I'm responding") — cancels escalation.
router.post(
  '/:alertId/ack',
  asyncHandler(async (req, res) => {
    const timer = pending.get(req.params.alertId);
    if (timer) {
      clearTimeout(timer);
      pending.delete(req.params.alertId);
    }
    const log = await prisma.activityLog.findUnique({ where: { id: req.params.alertId } });
    if (log) {
      await prisma.activityLog.update({
        where: { id: req.params.alertId },
        data: { payload: { ...(log.payload || {}), acked: true, ackedBy: req.user.id, ackedAt: new Date().toISOString() } },
      });
      // Tell the admin who triggered it that the user responded.
      req.app.get('io')?.to(`user:${log.actorId}`).emit('emergency.acked', {
        alertId: req.params.alertId,
        userId: req.user.id,
        userName: req.user.name,
      });
    }
    res.json({ ok: true });
  })
);

module.exports = router;
