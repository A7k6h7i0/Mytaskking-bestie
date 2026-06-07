'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const service = require('./calls.service');
const audit = require('../../services/audit');
const fcm = require('../../services/fcm');
const prisma = require('../../database/prisma');
const agora = require('../../services/agora');
const notificationActions = require('../../services/notificationActions');
const { Forbidden } = require('../../utils/errors');

// Date range for talk-time reports — defaults to the last 30 days.
const talkTimeRange = {
  query: Joi.object({
    from: Joi.date().iso().default(() => new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
    to: Joi.date().iso().default(() => new Date()),
  }),
};
const isAdminRole = (user) => ['SUPER_ADMIN', 'ADMIN'].includes(user.role);

const router = Router();
router.use(requireAuth);

function emitToCallParticipants(io, call, event, payload) {
  for (const p of call?.participants || []) {
    io?.to(`user:${p.userId}`).emit(event, payload);
  }
}

router.post(
  '/initiate',
  validate({
    body: Joi.object({
      participantIds: Joi.array().items(Joi.string()).min(1).required(),
      kind: Joi.string().valid('ONE_TO_ONE', 'GROUP'),
      channelId: Joi.string().allow(null, ''),
      // Voice vs video isn't persisted on the Call model yet — it's purely
      // a hint for the receiving client's ringer + Agora init. Accept it
      // here, default to VIDEO, and pass it through the socket emit below.
      mode: Joi.string().valid('VOICE', 'VIDEO'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const mode = req.body.mode || 'VIDEO';
    const result = await service.initiate({
      initiator: req.user,
      participantIds: req.body.participantIds,
      kind: req.body.kind,
      channelId: req.body.channelId,
    });
    audit.record({
      kind: 'call.initiated',
      entity: 'call',
      entityId: result.call.id,
      payload: { kind: result.call.kind, mode, participants: req.body.participantIds.length + 1 },
      req,
    });
    const io = req.app.get('io');
    for (const p of result.call.participants) {
      io?.to(`user:${p.userId}`).emit('call.incoming', {
        call: result.call,
        mode,
        token: result.tokens[p.userId],
      });
    }
    // FCM push to every invited participant so the recipient's phone rings
    // even when the app is backgrounded or killed. The Flutter side reads
    // the `type` / `callId` data fields to know to show the ringer.
    const inviteeIds = result.call.participants
      .map((p) => p.userId)
      .filter((uid) => uid !== req.user.id);
    if (inviteeIds.length) {
      prisma.deviceToken
        .findMany({ where: { userId: { in: inviteeIds } } })
        .then(async (devices) => {
          if (!devices.length) return null;
          const byUser = new Map();
          for (const device of devices) {
            const tokens = byUser.get(device.userId) || [];
            tokens.push(device.token);
            byUser.set(device.userId, tokens);
          }
          await Promise.all(
            Array.from(byUser.entries()).map(([userId, tokens]) =>
              fcm.sendToTokens(tokens, {
                title: `Incoming ${mode.toLowerCase()} call`,
                body: `${req.user.name} is calling...`,
                data: {
                  type: 'call.incoming',
                  callId: result.call.id,
                  mode,
                  fromName: req.user.name,
                  apiBaseUrl: notificationActions.publicApiBaseUrl(),
                  actionToken: notificationActions.signAction(
                    { action: 'call.decline', userId, callId: result.call.id },
                    '2m'
                  ),
                },
              })
            )
          );
          return null;
        })
        .catch(() => {/* push is best-effort */});
    }
    // 60-second auto-miss: if no one has joined within a minute, mark the
    // call MISSED and post a system message so the recipient still sees it
    // in their chat history with a tap-to-call-back affordance.
    setTimeout(async () => {
      try {
        // Atomic: only marks MISSED if still RINGING (won't kill a call that
        // was answered in the race window) and posts the "Missed call" event.
        const missed = await service.expireIfRinging({ callId: result.call.id });
        if (!missed) return;
        emitToCallParticipants(req.app.get('io'), missed, 'call.declined', { callId: missed.id, status: 'MISSED' });
        emitToCallParticipants(req.app.get('io'), missed, 'call.ended', { callId: missed.id, status: 'MISSED' });
      } catch (_) {/* job runner cleans up stragglers */}
    }, 60 * 1000);
    res.status(201).json({ ...result, mode });
  })
);

router.get(
  '/:id/token',
  asyncHandler(async (req, res) => res.json(await service.tokenFor({ callId: req.params.id, user: req.user })))
);

router.post('/:id/join', asyncHandler(async (req, res) => {
  const call = await service.join({ callId: req.params.id, user: req.user });
  // The client sends the random per-device uid it actually joined Agora with
  // (wildcard token flow); fall back to the derived uid for old clients.
  const agoraUid = Number(req.body?.agoraUid) > 0
    ? Number(req.body.agoraUid)
    : agora.toAgoraUid(req.user.id);
  emitToCallParticipants(req.app.get('io'), call, 'call.participant.joined', {
    callId: call.id,
    userId: req.user.id,
    userName: req.user.name,
    agoraUid,
  });
  res.json(call);
}));

// Re-broadcast a participant's real Agora uid + name so every device can label
// its tiles correctly — used for bidirectional discovery when devices join at
// different times (and to support the same account on multiple devices).
router.post(
  '/:id/announce',
  validate({
    body: Joi.object({
      agoraUid: Joi.number().required(),
      userName: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const call = await prisma.call.findUnique({
      where: { id: req.params.id },
      include: { participants: true },
    });
    if (!call) return res.json({ ok: true });
    // Only an actual participant may announce on a call — otherwise any
    // authenticated user could inject/relabel tiles in a call they aren't in.
    const isParticipant = (call.participants || []).some((p) => p.userId === req.user.id);
    if (!isParticipant) return res.status(403).json({ error: 'Not a participant' });
    emitToCallParticipants(req.app.get('io'), call, 'call.announce', {
      callId: call.id,
      userId: req.user.id,
      // Always use the authenticated user's real name — never trust a
      // client-supplied display name for someone else's tile.
      userName: req.user.name,
      agoraUid: Number(req.body.agoraUid),
    });
    res.json({ ok: true });
  })
);

router.post('/:id/leave', asyncHandler(async (req, res) => {
  const call = await service.leave({ callId: req.params.id, user: req.user });
  emitToCallParticipants(req.app.get('io'), call, 'call.participant.left', {
    callId: call.id,
    userId: req.user.id,
    status: call.status,
  });
  if (call.status === 'ENDED') {
    emitToCallParticipants(req.app.get('io'), call, 'call.ended', {
      callId: call.id,
      userId: req.user.id,
      status: call.status,
    });
  }
  res.json(call);
}));

router.post('/:id/decline', asyncHandler(async (req, res) => {
  const call = await service.decline({ callId: req.params.id, user: req.user });
  emitToCallParticipants(req.app.get('io'), call, 'call.declined', {
    callId: call.id,
    userId: req.user.id,
    status: call.status,
  });
  if (call.status === 'ENDED' || call.status === 'MISSED') {
    emitToCallParticipants(req.app.get('io'), call, 'call.ended', {
      callId: call.id,
      userId: req.user.id,
      status: call.status,
    });
  }
  res.json(call);
}));

router.post(
  '/:id/participants',
  validate({
    body: Joi.object({
      userId: Joi.string(),
      userIds: Joi.array().items(Joi.string()).min(1),
      mode: Joi.string().valid('VOICE', 'VIDEO'),
    }).or('userId', 'userIds'),
  }),
  asyncHandler(async (req, res) => {
    const userIds = Array.from(
      new Set([
        ...(req.body.userId ? [req.body.userId] : []),
        ...((Array.isArray(req.body.userIds) ? req.body.userIds : [])),
      ])
    );
    const mode = (req.body.mode || 'VIDEO').toUpperCase();
    const result = await service.addParticipant({
      callId: req.params.id,
      userIds,
      actor: req.user,
    });
    for (const userId of userIds) {
      req.app.get('io')?.to(`user:${userId}`).emit('call.invited', {
        call: result.call,
        mode,
        token: result.tokens[userId],
      });
    }
    // Ring the newly-added people even when their app is backgrounded/killed —
    // the socket-only `call.invited` above never reached them otherwise (the
    // "added but no incoming call" bug). Mirrors the FCM push in /initiate.
    prisma.deviceToken
      .findMany({ where: { userId: { in: userIds } } })
      .then(async (devices) => {
        if (!devices.length) return null;
        const byUser = new Map();
        for (const device of devices) {
          const tokens = byUser.get(device.userId) || [];
          tokens.push(device.token);
          byUser.set(device.userId, tokens);
        }
        await Promise.all(
          Array.from(byUser.entries()).map(([userId, tokens]) =>
            fcm.sendToTokens(tokens, {
              title: `Incoming ${mode.toLowerCase()} call`,
              body: `${req.user.name} is calling...`,
              data: {
                type: 'call.incoming',
                callId: result.call.id,
                mode,
                fromName: req.user.name,
                apiBaseUrl: notificationActions.publicApiBaseUrl(),
                actionToken: notificationActions.signAction(
                  { action: 'call.decline', userId, callId: result.call.id },
                  '2m'
                ),
              },
            })
          )
        );
        return null;
      })
      .catch(() => {/* push is best-effort */});
    res.json(result);
  })
);

router.post(
  '/:id/mute',
  validate({ body: Joi.object({ muted: Joi.boolean().required() }) }),
  asyncHandler(async (req, res) => {
    await service.setMuted({ callId: req.params.id, user: req.user, muted: req.body.muted });
    req.app.get('io')?.emit('call.participant.muted', {
      callId: req.params.id,
      userId: req.user.id,
      muted: req.body.muted,
    });
    res.json({ ok: true });
  })
);

router.get(
  '/history',
  validate({
    query: Joi.object({
      page: Joi.number().integer().min(1).default(1),
      pageSize: Joi.number().integer().min(1).max(100).default(25),
    }),
  }),
  asyncHandler(async (req, res) => res.json(await service.history({ user: req.user, ...req.query })))
);

// ----- talk-time reports (#12) -----
// Individual report for the signed-in user.
router.get(
  '/talk-time/me',
  validate(talkTimeRange),
  asyncHandler(async (req, res) =>
    res.json(await service.talkTimeForUser({ userId: req.user.id, from: req.query.from, to: req.query.to })))
);

// Org-wide consolidated report (admins only): per-employee rows + ranking.
router.get(
  '/talk-time/org',
  requireAdmin,
  validate(talkTimeRange),
  asyncHandler(async (req, res) =>
    res.json(await service.talkTimeOrg({ from: req.query.from, to: req.query.to })))
);

// Individual report for a specific user — self, or any admin.
router.get(
  '/talk-time/user/:userId',
  validate(talkTimeRange),
  asyncHandler(async (req, res) => {
    if (req.params.userId !== req.user.id && !isAdminRole(req.user)) {
      throw Forbidden('You can only view your own talk-time report');
    }
    res.json(await service.talkTimeForUser({ userId: req.params.userId, from: req.query.from, to: req.query.to }));
  })
);

// ----- recording -----
// The client records the mixed channel audio locally, uploads it as a
// FileAsset, then posts the resulting URL here so it's attached to the call
// and surfaces in the admin recordings panel.
router.post(
  '/:id/recording',
  validate({
    body: Joi.object({
      fileId: Joi.string().allow(null, ''),
      url: Joi.string().allow(null, ''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const call = await prisma.call.findUnique({
      where: { id: req.params.id },
      include: { participants: true },
    });
    if (!call) return res.status(404).json({ error: 'Call not found' });
    const isParticipant =
      call.initiatorId === req.user.id ||
      (call.participants || []).some((p) => p.userId === req.user.id);
    if (!isParticipant) return res.status(403).json({ error: 'Not a participant' });
    let url = req.body.url || null;
    if (!url && req.body.fileId) {
      const file = await prisma.fileAsset.findUnique({ where: { id: req.body.fileId } });
      url = file?.url || null;
    }
    if (!url) return res.status(400).json({ error: 'Recording url required' });
    const updated = await prisma.call.update({
      where: { id: call.id },
      data: { recordingUrl: url },
    });
    audit.record({
      kind: 'call.recording.saved',
      entity: 'call',
      entityId: call.id,
      payload: { url },
      req,
    });
    res.json({ ok: true, recordingUrl: updated.recordingUrl });
  })
);

// ----- screen sharing -----
// Agora screen share uses a separate logical UID on the same channelName so
// the publisher's camera/mic stream and screen stream are independently
// subscribable. We mint a new token with a screen-only UID.
router.post(
  '/:id/screen-share/token',
  asyncHandler(async (req, res) => {
    const result = await service.screenShareToken({ callId: req.params.id, user: req.user });
    req.app.get('io')?.emit('call.screen_share.started', { callId: req.params.id, userId: req.user.id });
    res.json(result);
  })
);

router.post(
  '/:id/screen-share/stop',
  asyncHandler(async (req, res) => {
    req.app.get('io')?.emit('call.screen_share.stopped', { callId: req.params.id, userId: req.user.id });
    res.json({ ok: true });
  })
);

// ----- raise hand / lower hand -----
router.post(
  '/:id/raise-hand',
  validate({ body: Joi.object({ raised: Joi.boolean().required() }) }),
  asyncHandler(async (req, res) => {
    req.app.get('io')?.emit('call.hand_raised', {
      callId: req.params.id,
      userId: req.user.id,
      raised: req.body.raised,
    });
    res.json({ ok: true });
  })
);

// ----- active speaker telemetry -----
// Clients post these periodically; server fans them out so other participants
// can highlight the active speaker. Volume is 0–255 (Agora's report scale).
router.post(
  '/:id/speaking',
  validate({ body: Joi.object({ volume: Joi.number().min(0).max(255).required() }) }),
  asyncHandler(async (req, res) => {
    req.app.get('io')?.emit('call.speaking', {
      callId: req.params.id,
      userId: req.user.id,
      volume: req.body.volume,
    });
    res.json({ ok: true });
  })
);

module.exports = router;
