'use strict';

const { nanoid } = require('nanoid');
const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const agora = require('../../services/agora');
const LIVE_RINGING_WINDOW_MS = 90 * 1000;
const MAX_ACTIVE_CALL_AGE_MS = 24 * 60 * 60 * 1000;

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

/**
 * Posts a CALL_EVENT message in the chat channel a call belongs to (if any),
 * so the timeline shows "📞 Missed call from Priya · 2:14 PM" instead of the
 * call vanishing silently. Safe no-op when the call has no associated channel.
 */
async function postCallEventMessage({ call, kind, actor }) {
  if (!call?.channelId) return;
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
  const body = `${text}|call:${call.id}:${status}`;
  try {
    const channel = await prisma.channel.findUnique({ where: { id: call.channelId } });
    if (!channel) return;
    return await prisma.message.create({
      data: {
        channelId: call.channelId,
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
            { status: 'RINGING', createdAt: { gte: staleBefore } },
          ],
          participants: { some: { userId: targetId, leftAt: null } },
        },
        select: { id: true, status: true },
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

  const all = Array.from(new Set([initiator.id, ...participantIds]));
  const call = await prisma.call.create({
    data: {
      channelName: makeChannelName(),
      kind: realKind,
      status: 'RINGING',
      initiatorId: initiator.id,
      channelId,
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

async function tokenFor({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  if (!['RINGING', 'ACTIVE'].includes(call.status)) throw BadRequest('Call has ended');
  const isParticipant = call.participants.some((p) => p.userId === user.id && !p.leftAt);
  if (!isParticipant) throw Forbidden('Not a participant of this call');
  return {
    ...agora.generateRtcToken({ channelName: call.channelName, wildcard: true }),
    call: withAgoraParticipantUids(call),
  };
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

async function join({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  if (!['RINGING', 'ACTIVE'].includes(call.status)) throw BadRequest('Call has ended');
  const part = call.participants.find((p) => p.userId === user.id);
  if (!part || part.leftAt) throw Forbidden('Not invited');

  await prisma.callParticipant.update({
    where: { callId_userId: { callId, userId: user.id } },
    data: { joinedAt: part.joinedAt || new Date() },
  });
  if (call.status === 'RINGING') {
    await prisma.call.update({ where: { id: callId }, data: { status: 'ACTIVE', startedAt: new Date() } });
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

async function leave({ callId, user }) {
  const before = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!before) throw NotFound('Call not found');
  if (!before.participants.some((p) => p.userId === user.id)) {
    throw Forbidden('Not a participant of this call');
  }
  if (['ENDED', 'MISSED', 'FAILED'].includes(before.status)) return before;

  await prisma.callParticipant.updateMany({
    where: { callId, userId: user.id, leftAt: null },
    data: { leftAt: new Date() },
  });
  if (before.kind === 'ONE_TO_ONE') {
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

async function acceptWaitingCall({ waitingCallId, user }) {
  const waitingCall = await prisma.call.findUnique({ where: { id: waitingCallId }, include: callInclude });
  if (!waitingCall) throw NotFound('Waiting call not found');
  if (!waitingCall.participants.some((p) => p.userId === user.id)) throw Forbidden('Not invited');

  const waitingUsers = waitingCall.participants
    .map((p) => p.userId)
    .filter((id) => id !== user.id);
  const activeCall = await prisma.call.findFirst({
    where: {
      id: { not: waitingCallId },
      status: 'ACTIVE',
      AND: [
        {
          participants: {
            some: { userId: user.id, joinedAt: { not: null }, leftAt: null },
          },
        },
        {
          participants: {
            some: { userId: { not: user.id }, joinedAt: { not: null }, leftAt: null },
          },
        },
      ],
    },
    include: callInclude,
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
    select: { id: true, name: true, role: true },
  });
  if (!target) throw NotFound('Target user not found');
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
  const allowed = call.participants.some((p) => p.userId === user.id) || ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
  if (!allowed) throw Forbidden('Not a participant of this call');
  return prisma.call.update({
    where: { id: callId },
    data: { notes: notes?.trim() || null },
    include: callInclude,
  });
}

// Atomically mark a still-RINGING call MISSED (the 60s no-answer timeout) and
// post the "Missed call" chat event. Conditional updateMany guarantees we never
// clobber a call that was answered in the race window.
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
async function talkTimeOrg({ from, to }) {
  const now = new Date();
  const parts = await prisma.callParticipant.findMany({
    where: { call: { createdAt: { gte: from, lte: to } } },
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
  talkTimeForUser,
  talkTimeOrg,
};
