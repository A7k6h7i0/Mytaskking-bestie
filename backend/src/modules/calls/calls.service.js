'use strict';

const { nanoid } = require('nanoid');
const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const agora = require('../../services/agora');
const tenant = require('../../services/tenant');
const LIVE_RINGING_WINDOW_MS = 90 * 1000;
const MAX_ACTIVE_CALL_AGE_MS = 24 * 60 * 60 * 1000;
/** Outbound ring with no answer → MISSED after this many ms (WhatsApp-style). */
const RING_NO_ANSWER_MS = Number(process.env.CALL_RING_TIMEOUT_MS) || 60 * 1000;

const callInclude = {
  participants: { include: { user: { select: { id: true, name: true, avatarUrl: true, role: true, customTitle: true, isClient: true } } } },
  initiator: { select: { id: true, name: true, avatarUrl: true, role: true, customTitle: true } },
};

function makeChannelName() {
  return `call_${nanoid(10)}`;
}

function fmtTime(date = new Date()) {
  return date.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    timeZone: 'Asia/Kolkata',
  });
}

function fmtDuration(ms) {
  if (!ms || ms < 0) return null;
  const totalMinutes = Math.max(1, Math.round(ms / 60000));
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  if (h && m) return `${h}h ${m}m`;
  if (h) return `${h}h`;
  return `${m}m`;
}

/** DM between two users (if one exists). */
async function findDmChannelId(userIdA, userIdB) {
  if (!userIdA || !userIdB || userIdA === userIdB) return null;
  const channel = await prisma.channel.findFirst({
    where: {
      kind: 'DM',
      archived: false,
      AND: [
        { members: { some: { userId: userIdA } } },
        { members: { some: { userId: userIdB } } },
        { members: { none: { userId: { notIn: [userIdA, userIdB] } } } },
      ],
    },
    select: { id: true },
  });
  return channel?.id || null;
}

/**
 * Where a call timeline event should land in chat.
 * Decline/miss about person X belongs in the host↔X DM (e.g. Kalyan declined
 * → Lakshmiraj–Kalyan chat), not the channel where the call originally started
 * (e.g. Lakshmiraj–Sarif).
 */
async function resolveCallEventChannelId({ call, kind, actor }) {
  if (
    (kind === 'DECLINED' || kind === 'MISSED') &&
    actor?.id &&
    call?.initiatorId &&
    actor.id !== call.initiatorId
  ) {
    const dm = await findDmChannelId(call.initiatorId, actor.id);
    if (dm) return dm;
  }
  return call?.channelId || null;
}

/**
 * Posts a CALL_EVENT message in the chat channel a call belongs to (if any),
 * so the timeline shows "📞 Missed call from Priya · 2:14 PM" instead of the
 * call vanishing silently. Safe no-op when the call has no associated channel.
 */
async function postCallEventMessage({ call, kind, actor }) {
  // Group calls: per-person decline / no-answer should not spam DMs.
  if (call?.kind === 'GROUP' && (kind === 'DECLINED' || kind === 'MISSED')) {
    return;
  }
  const channelId = await resolveCallEventChannelId({ call, kind, actor });
  if (!channelId) return;
  const initiatorName = call.initiator?.name || 'Someone';
  const now = new Date();
  const started = call.startedAt || call.createdAt || now;
  const duration = fmtDuration(now.getTime() - new Date(started).getTime());
  const text =
    kind === 'MISSED'   ? `📞 Missed call from ${initiatorName} · ${fmtTime(now)}` :
    kind === 'DECLINED' ? `📞 ${actor?.name || 'A teammate'} declined the call · ${fmtTime(now)}` :
    kind === 'STARTED'  ? `📞 ${initiatorName} started a ${call.kind === 'GROUP' ? 'group call' : 'call'} · ${fmtTime(now)}` :
    kind === 'ENDED'    ? `📞 Call ended · ${fmtTime(now)}${duration ? ` · ${duration}` : ''}` :
                          `📞 Call event`;
  // Append a pipe-delimited trailer with the call id + status so the
  // Flutter chat bubble can offer a tap-to-join affordance (like WhatsApp).
  // The Message model has no JSON `data` column yet — a deterministic
  // suffix string is the lightest-weight way to carry the metadata until
  // we run a migration.
  const status =
    kind === 'STARTED' ? 'ACTIVE' :
    kind === 'ENDED'   ? 'ENDED'  :
    kind === 'MISSED'  ? 'MISSED' :
    kind === 'DECLINED'? 'DECLINED': 'UNKNOWN';
  const body = `${text}|call:${call.id}:${status}:${call.initiatorId || ''}`;
  try {
    const channel = await prisma.channel.findUnique({ where: { id: channelId } });
    if (!channel) return;
    return await prisma.message.create({
      data: {
        channelId,
        authorId: actor?.id || call.initiatorId,
        kind: 'CALL_EVENT',
        body,
      },
    });
  } catch (_) {
    // Don't let a missing chat channel break call lifecycle.
  }
}

async function initiate({ initiator, participantIds, kind = 'ONE_TO_ONE', channelId = null }) {
  if (!participantIds || participantIds.length === 0) throw BadRequest('Need at least one participant');
  const uniqueParticipantIds = [...new Set(participantIds.filter(Boolean))];
  if (tenant.MULTI_TENANT) {
    const allowed = await prisma.user.findMany({
      where: tenant.tenantClause(initiator, {
        id: { in: uniqueParticipantIds },
        status: 'ACTIVE',
      }),
      select: { id: true },
    });
    if (allowed.length !== uniqueParticipantIds.length) {
      throw Forbidden('All call participants must belong to your organisation');
    }
  }
  if (!['ADMIN', 'SUPER_ADMIN'].includes(initiator.role)) {
    const protectedTargets = await prisma.user.count({
      where: {
        id: { in: uniqueParticipantIds },
        role: { in: ['ADMIN', 'SUPER_ADMIN'] },
      },
    });
    if (protectedTargets > 0) {
      throw Forbidden('Only admins can call administrators');
    }
  }
  const realKind = participantIds.length > 1 ? 'GROUP' : kind;
  let targetPresence = null;
  if (realKind === 'ONE_TO_ONE' && participantIds.length === 1) {
    const targetId = participantIds[0];
    const staleBefore = new Date(Date.now() - LIVE_RINGING_WINDOW_MS);
    const staleActiveBefore = new Date(Date.now() - MAX_ACTIVE_CALL_AGE_MS);
    // Drop abandoned outbound rings from this caller to the same person so a
    // retry is not falsely blocked as "already receiving another call".
    const ownStaleRinging = await prisma.call.findMany({
      where: {
        status: 'RINGING',
        initiatorId: initiator.id,
        participants: { some: { userId: targetId, leftAt: null } },
      },
      select: { id: true },
    }).catch(() => []);
    await Promise.all(ownStaleRinging.map(({ id }) => expireIfRinging({ callId: id })));
    const staleRinging = await prisma.call.findMany({
      where: {
        status: 'RINGING',
        createdAt: { lt: staleBefore },
        participants: { some: { userId: targetId, leftAt: null } },
      },
      select: { id: true },
    }).catch(() => []);
    await Promise.all(staleRinging.map(({ id }) => expireIfRinging({ callId: id })));
    const staleActive = await prisma.call.findMany({
      where: {
        status: 'ACTIVE',
        startedAt: { lt: staleActiveBefore },
        participants: { some: { userId: targetId, leftAt: null } },
      },
      select: { id: true },
    }).catch(() => []);
    await Promise.all(staleActive.map(({ id }) => expireStaleActive({ callId: id })));
    const [presence, activeCall] = await Promise.all([
      prisma.userPresence.findUnique({ where: { userId: targetId } }).catch(() => null),
      prisma.call.findFirst({
        where: {
          OR: [
            {
              status: 'ACTIVE',
              AND: [
                {
                  participants: {
                    some: { userId: targetId, joinedAt: { not: null }, leftAt: null },
                  },
                },
                {
                  participants: {
                    some: { userId: { not: targetId }, joinedAt: { not: null }, leftAt: null },
                  },
                },
              ],
            },
            {
              status: 'RINGING',
              createdAt: { gte: staleBefore },
              // Only block when someone *else* is already ringing this person.
              initiatorId: { not: initiator.id },
            },
          ],
          participants: { some: { userId: targetId, leftAt: null } },
        },
        select: { id: true, status: true, initiatorId: true },
      }).catch(() => null),
    ]);
    if (activeCall?.status === 'ACTIVE') {
      targetPresence = {
        status: 'ON_CALL',
        customStatus: 'Currently on another call',
        activeCallId: activeCall.id,
      };
    } else if (activeCall?.status === 'RINGING') {
      // A person who is already receiving another call is unavailable, but
      // there is no active conference to merge into. Do not expose a broken
      // call-waiting Accept action in this state.
      targetPresence = {
        status: 'BUSY',
        customStatus: 'Already receiving another call',
      };
    } else if (presence && ['BUSY', 'IN_MEETING', 'INVISIBLE', 'AWAY'].includes(presence.status)) {
      targetPresence = { status: presence.status, customStatus: presence.customStatus || null };
    }
  }

  // Target is unavailable (busy/away/etc.) — tell the caller without creating
  // a phantom call that is immediately marked missed.
  if (targetPresence && targetPresence.status !== 'ON_CALL') {
    return {
      call: null,
      targetPresence,
      suppressRinging: true,
      tokens: {},
    };
  }

  const all = Array.from(new Set([initiator.id, ...participantIds]));
  const call = await prisma.call.create({
    data: {
      channelName: makeChannelName(),
      kind: realKind,
      status: 'RINGING',
      initiatorId: initiator.id,
      channelId,
      tenantId: initiator.tenantId,
      participants: { create: all.map((uid) => ({ userId: uid })) },
    },
    include: callInclude,
  });

  // Wildcard tokens: each device picks its own random uid at join time so the
  // same account can be in the call from multiple devices without colliding.
  const tokenForUser = () => agora.generateRtcToken({ channelName: call.channelName, wildcard: true });
  if (!targetPresence) await postCallEventMessage({ call, kind: 'STARTED', actor: initiator });

  return {
    call,
    targetPresence,
    suppressRinging: !!targetPresence,
    tokens: Object.fromEntries(all.map((uid) => [uid, tokenForUser(uid)])),
  };
}

/** True when the room has more than two people (even if kind was never promoted). */
function isMultiPartyCall(call) {
  if (!call) return false;
  if (call.kind === 'GROUP') return true;
  return (call.participants || []).length > 2;
}

/** Someone who left can return while the call is still ACTIVE and others remain. */
function canRejoinAfterLeave(call, part) {
  if (!part?.leftAt) return true;
  if (!['RINGING', 'ACTIVE'].includes(call?.status)) return false;
  if (isMultiPartyCall(call)) return true;
  const othersStillIn = (call.participants || []).filter(
    (p) => p.userId !== part.userId && p.joinedAt && !p.leftAt,
  ).length;
  return call.status === 'ACTIVE' && othersStillIn > 0;
}

function withAgoraParticipantUids(call) {
  if (!call) return call;
  return {
    ...call,
    participants: (call.participants || []).map((p) => ({
      ...p,
      agoraUid: agora.toAgoraUid(p.userId),
    })),
  };
}

async function tokenFor({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  if (!['RINGING', 'ACTIVE'].includes(call.status)) throw BadRequest('Call has ended');
  const part = call.participants.find((p) => p.userId === user.id);
  if (!part) throw Forbidden('Not a participant of this call');
  if (part.leftAt && !canRejoinAfterLeave(call, part)) {
    throw Forbidden('Not a participant of this call');
  }
  return {
    ...agora.generateRtcToken({ channelName: call.channelName, wildcard: true }),
    call: withAgoraParticipantUids(call),
  };
}

async function join({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  if (!['RINGING', 'ACTIVE'].includes(call.status)) throw BadRequest('Call has ended');
  const part = call.participants.find((p) => p.userId === user.id);
  if (!part) throw Forbidden('Not invited');
  if (part.leftAt && !canRejoinAfterLeave(call, part)) {
    throw Forbidden('Not invited');
  }

  if (call.kind === 'ONE_TO_ONE' && isMultiPartyCall(call)) {
    await prisma.call.update({ where: { id: callId }, data: { kind: 'GROUP' } });
  }

  await prisma.callParticipant.update({
    where: { callId_userId: { callId, userId: user.id } },
    data: {
      leftAt: null,
      joinedAt: part.joinedAt || new Date(),
    },
  });
  if (call.status === 'RINGING') {
    if (call.kind === 'ONE_TO_ONE' && !isMultiPartyCall(call)) {
      // Stay RINGING until the callee actually answers — otherwise the 60s
      // no-answer timer never fires and the caller can sit on "Ringing…" forever
      // while the callee never received the invite.
      const answered = await prisma.callParticipant.count({
        where: {
          callId,
          userId: { not: call.initiatorId },
          joinedAt: { not: null },
          leftAt: null,
        },
      });
      if (answered > 0) {
        await prisma.call.update({
          where: { id: callId },
          data: { status: 'ACTIVE', startedAt: new Date() },
        });
      }
    } else {
      await prisma.call.update({
        where: { id: callId },
        data: { status: 'ACTIVE', startedAt: new Date() },
      });
    }
  }
  return prisma.call
    .findUnique({ where: { id: callId }, include: callInclude })
    .then(withAgoraParticipantUids);
}

/**
 * #7 Call timer validation. Computes the call's talk duration two independent
 * ways and reconciles them before finalizing the record:
 *   1. call-level:  endedAt - startedAt
 *   2. participant: max over participants of (leftAt|endedAt) - joinedAt
 * If the call-level value is missing/invalid (no startedAt, negative, or wildly
 * off the participant value), the participant value is used. startedAt is
 * backfilled from the earliest join so the record is accurate. Returns the
 * finalized duration in seconds and persists it.
 */
async function finalizeCallTiming(callId, endedAtInput) {
  const call = await prisma.call.findUnique({
    where: { id: callId },
    include: { participants: { select: { joinedAt: true, leftAt: true } } },
  });
  if (!call) return 0;
  const endedAt = endedAtInput || call.endedAt || new Date();
  const joins = call.participants.map((p) => p.joinedAt).filter(Boolean).map((d) => new Date(d).getTime());
  const earliestJoin = joins.length ? Math.min(...joins) : null;
  const startedAt = call.startedAt ? new Date(call.startedAt).getTime() : earliestJoin;

  // Primary (call-level) estimate.
  let primary = startedAt != null ? Math.floor((new Date(endedAt).getTime() - startedAt) / 1000) : null;
  // Cross-check (participant-level) estimate.
  let participantMax = 0;
  for (const p of call.participants) {
    if (!p.joinedAt) continue;
    const end = p.leftAt ? new Date(p.leftAt).getTime() : new Date(endedAt).getTime();
    participantMax = Math.max(participantMax, Math.floor((end - new Date(p.joinedAt).getTime()) / 1000));
  }
  participantMax = Math.max(0, participantMax);

  let duration;
  if (primary == null || primary < 0) {
    duration = participantMax; // call-level unusable → trust participants
  } else if (participantMax > 0 && Math.abs(primary - participantMax) > 5) {
    // The two disagree by more than 5s — re-check and prefer the participant
    // measure (it reflects actual connected time, not ring time).
    duration = Math.min(primary, participantMax + 2);
  } else {
    duration = primary;
  }
  duration = Math.max(0, duration);

  await prisma.call.update({
    where: { id: callId },
    data: {
      durationSeconds: duration,
      ...(call.startedAt == null && earliestJoin != null
        ? { startedAt: new Date(earliestJoin) }
        : {}),
    },
  }).catch(() => {});
  return duration;
}

function calleeHasAnswered(call) {
  return (call?.participants || []).some(
    (p) => p.userId !== call.initiatorId && p.joinedAt != null && !p.leftAt,
  );
}

async function leave({ callId, user }) {
  const before = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!before) throw NotFound('Call not found');
  if (!before.participants.some((p) => p.userId === user.id)) {
    throw Forbidden('Not a participant of this call');
  }
  if (['ENDED', 'MISSED', 'FAILED'].includes(before.status)) return before;

  // Caller hung up while still ringing — treat as no-answer, not a connected call.
  if (
    before.status === 'RINGING' &&
    before.kind === 'ONE_TO_ONE' &&
    !calleeHasAnswered(before)
  ) {
    const missed = await expireIfRinging({ callId });
    if (missed) return missed;
  }

  await prisma.callParticipant.updateMany({
    where: { callId, userId: user.id, leftAt: null },
    data: { leftAt: new Date() },
  });
  if (!isMultiPartyCall(before)) {
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
    });
    await finalizeCallTiming(callId);
    const ended = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
    await postCallEventMessage({ call: ended, kind: 'ENDED', actor: user });
    return ended;
  }
  if (before.kind === 'ONE_TO_ONE') {
    await prisma.call.update({ where: { id: callId }, data: { kind: 'GROUP' } });
  }
  // A group call cannot continue with one connected person. Ignore invited
  // users who never joined when deciding whether the room is still alive.
  const remainingConnected = await prisma.callParticipant.count({
    where: { callId, joinedAt: { not: null }, leftAt: null },
  });
  if (remainingConnected <= 1) {
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
    });
    await finalizeCallTiming(callId);
    const ended = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
    await postCallEventMessage({ call: ended, kind: 'ENDED', actor: user });
  }
  return prisma.call.findUnique({ where: { id: callId }, include: callInclude });
}

async function decline({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  const part = call.participants.find((p) => p.userId === user.id);
  if (!part) throw Forbidden('Not invited');

  await prisma.callParticipant.updateMany({
    where: { callId, userId: user.id, leftAt: null },
    data: { leftAt: new Date() },
  });

  if (call.status === 'RINGING' && call.kind === 'ONE_TO_ONE') {
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    // A missed (never-answered) call has no talk time.
    await prisma.call.update({ where: { id: callId }, data: { status: 'MISSED', endedAt: new Date(), durationSeconds: 0 } });
    await postCallEventMessage({ call, kind: 'MISSED', actor: user });
  } else if (call.status === 'RINGING') {
    const remainingInvitees = await prisma.callParticipant.count({
      where: {
        callId,
        userId: { not: call.initiatorId },
        leftAt: null,
      },
    });
    if (remainingInvitees === 0) {
      await prisma.callParticipant.updateMany({
        where: { callId, leftAt: null },
        data: { leftAt: new Date() },
      });
      await prisma.call.update({
        where: { id: callId },
        data: { status: 'MISSED', endedAt: new Date(), durationSeconds: 0 },
      });
      await postCallEventMessage({ call, kind: 'MISSED', actor: user });
    } else {
      await postCallEventMessage({ call, kind: 'DECLINED', actor: user });
    }
  } else if (call.kind === 'ONE_TO_ONE') {
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
    });
    await finalizeCallTiming(callId);
    const ended = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
    await postCallEventMessage({ call: ended, kind: 'DECLINED', actor: user });
  } else {
    await postCallEventMessage({ call, kind: 'DECLINED', actor: user });
  }

  return prisma.call.findUnique({ where: { id: callId }, include: callInclude });
}

async function addParticipant({ callId, userIds, actor }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  if (!['RINGING', 'ACTIVE'].includes(call.status)) throw BadRequest('Call has ended');
  const actorParticipant = call.participants.some((p) => p.userId === actor.id);
  if (!actorParticipant && !['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
    throw Forbidden('Only current participants or admins can add people');
  }

  const safeUserIds = Array.from(new Set((userIds || []).map((value) => String(value || '').trim()).filter(Boolean)));
  if (!safeUserIds.length) throw BadRequest('Need at least one user to invite');

  for (const userId of safeUserIds) {
    await prisma.callParticipant.upsert({
      where: { callId_userId: { callId, userId } },
      update: { leftAt: null },
      create: { callId, userId },
    });
  }

  // converts a 1:1 call into a group call when 3+ participants
  const totalParticipants = await prisma.callParticipant.count({ where: { callId } });
  if (totalParticipants > 2 && call.kind === 'ONE_TO_ONE') {
    await prisma.call.update({ where: { id: callId }, data: { kind: 'GROUP' } });
  }

  const refreshed = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  return {
    call: refreshed,
    // Wildcard tokens so an invited user can also join from multiple devices,
    // consistent with initiate()/tokenFor().
    tokens: Object.fromEntries(
      safeUserIds.map((userId) => [userId, agora.generateRtcToken({ channelName: call.channelName, wildcard: true })])
    ),
  };
}

async function findActiveCallForUser(userId, { excludeCallId, preferredCallId } = {}) {
  if (preferredCallId) {
    const preferred = await prisma.call.findFirst({
      where: {
        id: preferredCallId,
        status: 'ACTIVE',
        participants: { some: { userId, leftAt: null } },
      },
      include: callInclude,
    });
    if (preferred) return preferred;
  }
  return prisma.call.findFirst({
    where: {
      ...(excludeCallId ? { id: { not: excludeCallId } } : {}),
      status: 'ACTIVE',
      participants: {
        some: { userId, leftAt: null, joinedAt: { not: null } },
      },
    },
    orderBy: { startedAt: 'desc' },
    include: callInclude,
  });
}

async function acceptWaitingCall({ waitingCallId, user, activeCallId }) {
  const waitingCall = await prisma.call.findUnique({ where: { id: waitingCallId }, include: callInclude });
  if (!waitingCall) throw NotFound('Waiting call not found');
  if (waitingCall.initiatorId === user.id) {
    throw Forbidden('The waiting caller cannot accept their own waiting call');
  }
  if (!waitingCall.participants.some((p) => p.userId === user.id && !p.leftAt)) {
    throw Forbidden('Not invited');
  }

  const waitingUsers = waitingCall.participants
    .filter((p) => !p.leftAt && p.userId !== user.id)
    .map((p) => p.userId);
  const activeCall = await findActiveCallForUser(user.id, {
    excludeCallId: waitingCallId,
    preferredCallId: activeCallId,
  });

  // Accept can arrive twice from a rapid double-tap or from both the native
  // notification and Flutter overlay. If the first request already merged
  // the caller, return the resulting conference instead of reporting a false
  // "Waiting call not found" error.
  if (waitingCall.status !== 'RINGING') {
    const alreadyMerged = activeCall &&
      waitingUsers.every((userId) =>
        activeCall.participants.some((p) => p.userId === userId && !p.leftAt)
      );
    if (!alreadyMerged) throw NotFound('Waiting call not found');
    return {
      activeCall,
      waitingCallId,
      tokens: Object.fromEntries(
        waitingUsers.map((userId) => [
          userId,
          agora.generateRtcToken({ channelName: activeCall.channelName, wildcard: true }),
        ])
      ),
      addedUserIds: waitingUsers,
    };
  }
  if (!activeCall) throw BadRequest('Your active call is no longer available');

  const added = await addParticipant({ callId: activeCall.id, userIds: waitingUsers, actor: user });
  const now = new Date();
  await prisma.$transaction([
    prisma.callParticipant.updateMany({
      where: { callId: waitingCallId, leftAt: null },
      data: { leftAt: now },
    }),
    prisma.call.update({
      where: { id: waitingCallId },
      data: { status: 'ENDED', endedAt: now, durationSeconds: 0 },
    }),
  ]);
  return {
    activeCall: added.call,
    waitingCallId,
    tokens: added.tokens,
    addedUserIds: waitingUsers,
  };
}

async function rejectWaitingCall({ waitingCallId, user }) {
  const call = await decline({ callId: waitingCallId, user });
  return { call, waitingCallId };
}

async function transfer({ callId, targetUserId, actor }) {
  if (targetUserId === actor.id) throw BadRequest('Choose another person');
  const target = await prisma.user.findUnique({
    where: { id: targetUserId },
    select: { id: true, name: true, role: true, tenantId: true },
  });
  if (!target) throw NotFound('Target user not found');
  tenant.assertSameTenant(actor, target.tenantId);
  if (
    !['ADMIN', 'SUPER_ADMIN'].includes(actor.role) &&
    ['ADMIN', 'SUPER_ADMIN'].includes(target.role)
  ) {
    throw Forbidden('Only admins can transfer calls to administrators');
  }
  const result = await addParticipant({ callId, userIds: [targetUserId], actor });
  return {
    ...result,
    targetUserId,
    targetName: target?.name || 'another person',
    transferredBy: { id: actor.id, name: actor.name },
  };
}

async function updateNotes({ callId, notes, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: { participants: true } });
  if (!call) throw NotFound('Call not found');
  tenant.assertSameTenant(user, call.tenantId);
  const allowed =
    call.participants.some((p) => p.userId === user.id) ||
    tenant.canAdministerTenant(user, call.tenantId);
  if (!allowed) throw Forbidden('Not a participant of this call');
  return prisma.call.update({
    where: { id: callId },
    data: { notes: notes?.trim() || null },
    include: callInclude,
  });
}

// Atomically mark a still-RINGING call MISSED (no-answer timeout) and post the
// "Missed call" / "No answer" chat event. Conditional updateMany guarantees we
// never clobber a call that was answered in the race window.
async function expireIfRinging({ callId }) {
  const now = new Date();
  const updated = await prisma.call.updateMany({
    where: { id: callId, status: 'RINGING' },
    data: { status: 'MISSED', endedAt: now, durationSeconds: 0 },
  });
  if (updated.count === 0) return null; // already answered / ended — no-op
  await prisma.callParticipant.updateMany({
    where: { callId, leftAt: null },
    data: { leftAt: now },
  });
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (call) await postCallEventMessage({ call, kind: 'MISSED', actor: call.initiator });
  return call;
}

/** Sweep every RINGING call older than RING_NO_ANSWER_MS — backs up in-memory setTimeout. */
async function expireStaleRingingCalls({ io = null } = {}) {
  const cutoff = new Date(Date.now() - RING_NO_ANSWER_MS);
  const stale = await prisma.call.findMany({
    where: { status: 'RINGING', createdAt: { lt: cutoff } },
    select: { id: true },
  });
  const expired = [];
  for (const { id } of stale) {
    const missed = await expireIfRinging({ callId: id });
    if (!missed) continue;
    expired.push(missed);
    if (io) {
      for (const p of missed.participants || []) {
        io.to(`user:${p.userId}`).emit('call.declined', { callId: missed.id, status: 'MISSED' });
        io.to(`user:${p.userId}`).emit('call.ended', { callId: missed.id, status: 'MISSED' });
      }
    }
  }
  return expired;
}

async function expireStaleActive({ callId }) {
  const now = new Date();
  const updated = await prisma.call.updateMany({
    where: { id: callId, status: 'ACTIVE' },
    data: { status: 'ENDED', endedAt: now },
  });
  if (updated.count === 0) return null;
  await prisma.callParticipant.updateMany({
    where: { callId, leftAt: null },
    data: { leftAt: now },
  });
  await finalizeCallTiming(callId, now);
  return prisma.call.findUnique({ where: { id: callId }, include: callInclude });
}

async function setMuted({ callId, user, muted }) {
  await prisma.callParticipant.update({
    where: { callId_userId: { callId, userId: user.id } },
    data: { muted: !!muted },
  });
}

async function history({ user, page = 1, pageSize = 25 }) {
  const where = {
    OR: [{ initiatorId: user.id }, { participants: { some: { userId: user.id } } }],
  };
  const [total, items] = await prisma.$transaction([
    prisma.call.count({ where }),
    prisma.call.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: callInclude,
    }),
  ]);
  return { total, page, pageSize, items };
}

async function screenShareToken({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  const isParticipant = call.participants.some((p) => p.userId === user.id);
  if (!isParticipant) throw Forbidden('Not a participant');

  // Agora convention: append a high bit to keep the screen UID distinct from
  // the camera/mic UID. Frontends publish a second stream on this UID.
  const screenUid = `screen_${user.id}`;
  const token = agora.generateRtcToken({ channelName: call.channelName, uid: screenUid });
  return { ...token, sharedBy: user.id };
}

// ───────────────────────────── Talk-time reports ─────────────────────────────

/** Seconds a participant was actually connected on a call. 0 if never joined. */
function _participantTalkSeconds(part, call, now) {
  if (!part.joinedAt) return 0;
  const end = part.leftAt || call.endedAt || now;
  const ms = new Date(end).getTime() - new Date(part.joinedAt).getTime();
  return Math.max(0, Math.floor(ms / 1000));
}

/** Individual talk-time totals for one user over [from, to]. */
async function talkTimeForUser({ userId, from, to }) {
  const now = new Date();
  const parts = await prisma.callParticipant.findMany({
    where: { userId, call: { createdAt: { gte: from, lte: to } } },
    include: {
      call: { select: { initiatorId: true, endedAt: true } },
    },
  });
  let totalSeconds = 0;
  let incomingSeconds = 0;
  let outgoingSeconds = 0;
  let calls = 0;
  let missed = 0;
  for (const p of parts) {
    if (!p.joinedAt) {
      missed += 1;
      continue;
    }
    const sec = _participantTalkSeconds(p, p.call, now);
    totalSeconds += sec;
    calls += 1;
    if (p.call.initiatorId === userId) {
      outgoingSeconds += sec;
    } else {
      incomingSeconds += sec;
    }
  }
  return {
    userId,
    from,
    to,
    totalSeconds,
    incomingSeconds,
    outgoingSeconds,
    calls,
    missed,
    averageSeconds: calls ? Math.round(totalSeconds / calls) : 0,
  };
}

/** Org-wide talk-time: per-employee rows, ranking, total and average. */
async function talkTimeOrg({ user, from, to }) {
  const now = new Date();
  const parts = await prisma.callParticipant.findMany({
    where: {
      call: tenant.tenantClause(user, { createdAt: { gte: from, lte: to } }),
    },
    include: {
      call: { select: { initiatorId: true, endedAt: true } },
      user: {
        select: {
          id: true,
          name: true,
          role: true,
          avatarUrl: true,
          isClient: true,
          customTitle: true,
          departmentId: true,
        },
      },
    },
  });
  const byUser = new Map();
  for (const p of parts) {
    if (!p.user || p.user.isClient) continue; // employees only
    const row = byUser.get(p.userId) || {
      user: p.user,
      totalSeconds: 0,
      incomingSeconds: 0,
      outgoingSeconds: 0,
      calls: 0,
      missed: 0,
    };
    if (!p.joinedAt) {
      row.missed += 1;
    } else {
      const sec = _participantTalkSeconds(p, p.call, now);
      row.totalSeconds += sec;
      row.calls += 1;
      if (p.call.initiatorId === p.userId) row.outgoingSeconds += sec;
      else row.incomingSeconds += sec;
    }
    byUser.set(p.userId, row);
  }
  const rows = Array.from(byUser.values()).sort(
    (a, b) => b.totalSeconds - a.totalSeconds
  );
  const totalCombinedSeconds = rows.reduce((s, r) => s + r.totalSeconds, 0);
  return {
    from,
    to,
    totalCombinedSeconds,
    averageSeconds: rows.length
      ? Math.round(totalCombinedSeconds / rows.length)
      : 0,
    employeeCount: rows.length,
    employees: rows.map((r, i) => ({
      rank: i + 1,
      userId: r.user.id,
      name: r.user.name,
      role: r.user.role,
      customTitle: r.user.customTitle,
      avatarUrl: r.user.avatarUrl,
      totalSeconds: r.totalSeconds,
      incomingSeconds: r.incomingSeconds,
      outgoingSeconds: r.outgoingSeconds,
      calls: r.calls,
      missed: r.missed,
    })),
  };
}

module.exports = {
  initiate,
  tokenFor,
  join,
  leave,
  decline,
  addParticipant,
  acceptWaitingCall,
  rejectWaitingCall,
  transfer,
  updateNotes,
  setMuted,
  history,
  screenShareToken,
  expireIfRinging,
  expireStaleRingingCalls,
  RING_NO_ANSWER_MS,
  talkTimeForUser,
  talkTimeOrg,
};
