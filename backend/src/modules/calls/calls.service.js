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

  const tokenForUser = (uid) => agora.generateRtcToken({ channelName: call.channelName, uid });

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
  return agora.generateRtcToken({ channelName: call.channelName, uid: user.id });
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
  return prisma.call.findUnique({ where: { id: callId }, include: callInclude });
}

async function leave({ callId, user }) {
  await prisma.callParticipant.updateMany({
    where: { callId, userId: user.id, leftAt: null },
    data: { leftAt: new Date() },
  });
  const remaining = await prisma.callParticipant.count({ where: { callId, leftAt: null } });
  if (remaining === 0) {
    await prisma.call.update({
      where: { id: callId },
      data: { status: 'ENDED', endedAt: new Date() },
    });
  }
  return prisma.call.findUnique({ where: { id: callId }, include: callInclude });
}

async function addParticipant({ callId, userId, actor }) {
  const call = await prisma.call.findUnique({ where: { id: callId }, include: callInclude });
  if (!call) throw NotFound('Call not found');
  if (call.initiatorId !== actor.id && !['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
    throw Forbidden('Only initiator can add participants');
  }
  await prisma.callParticipant.upsert({
    where: { callId_userId: { callId, userId } },
    update: {},
    create: { callId, userId },
  });

  // converts a 1:1 call into a group call when 3+ participants
  const totalParticipants = await prisma.callParticipant.count({ where: { callId } });
  if (totalParticipants > 2 && call.kind === 'ONE_TO_ONE') {
    await prisma.call.update({ where: { id: callId }, data: { kind: 'GROUP' } });
  }

  return {
    call: await prisma.call.findUnique({ where: { id: callId }, include: callInclude }),
    token: agora.generateRtcToken({ channelName: call.channelName, uid: userId }),
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
  addParticipant,
  setMuted,
  history,
  screenShareToken,
};
