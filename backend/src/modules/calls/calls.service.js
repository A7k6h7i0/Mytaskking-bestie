'use strict';

const { nanoid } = require('nanoid');
const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const agora = require('../../services/agora');

const callInclude = {
  participants: { include: { user: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } } } },
  initiator: { select: { id: true, name: true, avatarUrl: true } },
};

function makeChannelName() {
  return `call_${nanoid(10)}`;
}

function fmtTime(date = new Date()) {
  return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
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
  const realKind = participantIds.length > 1 ? 'GROUP' : kind;

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
  await postCallEventMessage({ call, kind: 'STARTED', actor: initiator });

  return {
    call,
    tokens: Object.fromEntries(all.map((uid) => [uid, tokenForUser(uid)])),
  };
}

async function tokenFor({ callId, user }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  const isParticipant = call.participants.some((p) => p.userId === user.id);
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
  const part = call.participants.find((p) => p.userId === user.id);
  if (!part) throw Forbidden('Not invited');

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

async function leave({ callId, user }) {
  const before = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!before) throw NotFound('Call not found');
  await prisma.callParticipant.updateMany({
    where: { callId, userId: user.id, leftAt: null },
    data: { leftAt: new Date() },
  });
  if (before.kind === 'ONE_TO_ONE') {
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    const ended = await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
      include: callInclude,
    });
    await postCallEventMessage({ call: ended, kind: 'ENDED', actor: user });
    return ended;
  }
  const remaining = await prisma.callParticipant.count({ where: { callId, leftAt: null } });
  if (remaining === 0) {
    const ended = await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
      include: callInclude,
    });
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

  if (call.status === 'RINGING') {
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    await prisma.call.update({ where: { id: callId }, data: { status: 'MISSED', endedAt: new Date() } });
    await postCallEventMessage({ call, kind: 'MISSED', actor: user });
  } else if (call.kind === 'ONE_TO_ONE') {
    const ended = await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
      include: callInclude,
    });
    await prisma.callParticipant.updateMany({
      where: { callId, leftAt: null },
      data: { leftAt: new Date() },
    });
    await postCallEventMessage({ call: ended, kind: 'DECLINED', actor: user });
  } else {
    await postCallEventMessage({ call, kind: 'DECLINED', actor: user });
  }

  return prisma.call.findUnique({ where: { id: callId }, include: callInclude });
}

async function addParticipant({ callId, userIds, actor }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  const actorParticipant = call.participants.some((p) => p.userId === actor.id);
  if (!actorParticipant && !['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
    throw Forbidden('Only current participants or admins can add people');
  }

  const safeUserIds = Array.from(new Set((userIds || []).map((value) => String(value || '').trim()).filter(Boolean)));
  if (!safeUserIds.length) throw BadRequest('Need at least one user to invite');

  for (const userId of safeUserIds) {
    await prisma.callParticipant.upsert({
      where: { callId_userId: { callId, userId } },
      update: {},
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
    tokens: Object.fromEntries(
      safeUserIds.map((userId) => [userId, agora.generateRtcToken({ channelName: call.channelName, uid: userId })])
    ),
  };
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

module.exports = {
  initiate,
  tokenFor,
  join,
  leave,
  decline,
  addParticipant,
  setMuted,
  history,
  screenShareToken,
};
