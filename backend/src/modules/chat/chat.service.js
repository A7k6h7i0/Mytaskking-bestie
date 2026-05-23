'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const channelsService = require('../channels/channels.service');
const notifications = require('../notifications/notifications.service');

async function listMessages(channelId, user, { cursor, limit = 40 } = {}) {
  await channelsService.ensureMember(channelId, user.id).catch((e) => {
    if (!['SUPER_ADMIN', 'ADMIN'].includes(user.role)) throw e;
  });
  const channel = await prisma.channel.findUnique({ where: { id: channelId }, select: { kind: true } });
  if (!channel) throw NotFound('Channel not found');
  if (user.isClient && channel.kind !== 'CLIENT') throw Forbidden('Clients can only access client channels');

  const messages = await prisma.message.findMany({
    where: { channelId, deletedAt: null, ...(cursor ? { id: { lt: cursor } } : {}) },
    take: Math.min(limit, 100),
    orderBy: { id: 'desc' },
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
      attachments: true,
      reactions: true,
      replyTo: { select: { id: true, body: true, authorId: true } },
    },
  });
  return { items: messages.reverse(), nextCursor: messages.length ? messages[0].id : null };
}

async function sendMessage({ channelId, user, body, kind = 'TEXT', attachmentIds = [], replyToId = null, threadRootId = null }) {
  await channelsService.ensureMember(channelId, user.id).catch((e) => {
    if (!['SUPER_ADMIN', 'ADMIN'].includes(user.role)) throw e;
  });
  const channel = await prisma.channel.findUnique({
    where: { id: channelId },
    include: {
      members: {
        include: {
          user: { select: { id: true, name: true, userId: true, isClient: true } },
        },
      },
    },
  });
  if (!channel) throw NotFound('Channel not found');
  if (user.isClient && channel.kind !== 'CLIENT') {
    throw Forbidden('Clients can only message inside client channels');
  }

  if (!body && (!attachmentIds || attachmentIds.length === 0)) {
    throw BadRequest('Message must contain body or attachments');
  }

  // Resolve the thread root — explicit threadRootId wins, otherwise inherit
  // from replyTo's thread (or use replyTo as the root if it's not yet threaded).
  let resolvedRootId = threadRootId;
  if (!resolvedRootId && replyToId) {
    const parent = await prisma.message.findUnique({
      where: { id: replyToId },
      select: { id: true, threadRootId: true },
    });
    resolvedRootId = parent?.threadRootId || parent?.id || null;
  }

  const message = await prisma.message.create({
    data: {
      channelId,
      authorId: user.id,
      body: body || null,
      kind,
      replyToId: replyToId || null,
      threadRootId: resolvedRootId || null,
      ...(attachmentIds.length ? { attachments: { connect: attachmentIds.map((id) => ({ id })) } } : {}),
    },
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
      attachments: true,
    },
  });

  // Update the thread root counters in the background — never block the send.
  if (resolvedRootId) {
    prisma.message.update({
      where: { id: resolvedRootId },
      data: { threadReplyCount: { increment: 1 }, threadLastReplyAt: new Date() },
    }).catch(() => {});
  }

  await prisma.channel.update({ where: { id: channelId }, data: { updatedAt: new Date() } });

  const mentionTargets = findMentionTargets({
    body: body || '',
    members: channel.members,
    authorId: user.id,
  });
  await Promise.all(
    mentionTargets.map((target) =>
      notifications.notify({
        userId: target.id,
        kind: 'MENTION',
        title: `${user.name} mentioned you`,
        body: channel.name ? `In #${channel.name}: ${body || 'New message'}` : body || 'You were mentioned in a client channel',
        data: { channelId, messageId: message.id, authorId: user.id },
      }).catch(() => {})
    )
  );

  return message;
}

function findMentionTargets({ body, members, authorId }) {
  const source = String(body || '').toLowerCase();
  if (!source.includes('@')) return [];
  const picks = [];
  for (const member of members || []) {
    const person = member.user;
    if (!person || person.id === authorId) continue;
    const nameKey = `@${String(person.name || '').trim().toLowerCase()}`;
    const userIdKey = `@${String(person.userId || '').trim().toLowerCase()}`;
    if ((person.userId && source.includes(userIdKey)) || (person.name && source.includes(nameKey))) {
      picks.push(person);
    }
  }
  return Array.from(new Map(picks.map((item) => [item.id, item])).values());
}

async function listThread({ rootId, user, limit = 100 }) {
  const root = await prisma.message.findUnique({
    where: { id: rootId },
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
      attachments: true,
      reactions: true,
    },
  });
  if (!root) throw NotFound('Thread not found');
  await channelsService.ensureMember(root.channelId, user.id).catch((e) => {
    if (!['SUPER_ADMIN', 'ADMIN'].includes(user.role)) throw e;
  });
  const channel = await prisma.channel.findUnique({ where: { id: root.channelId }, select: { kind: true } });
  if (!channel) throw NotFound('Channel not found');
  if (user.isClient && channel.kind !== 'CLIENT') throw Forbidden('Clients can only access client channels');

  const replies = await prisma.message.findMany({
    where: { threadRootId: rootId, deletedAt: null },
    orderBy: { createdAt: 'asc' },
    take: limit,
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true } },
      attachments: true,
      reactions: true,
    },
  });

  return { root, replies };
}

async function editMessage({ id, user, body }) {
  const m = await prisma.message.findUnique({ where: { id } });
  if (!m) throw NotFound('Message not found');
  if (m.authorId !== user.id) throw Forbidden('Only author can edit');
  return prisma.message.update({ where: { id }, data: { body, editedAt: new Date() } });
}

async function deleteMessage({ id, user }) {
  const m = await prisma.message.findUnique({ where: { id } });
  if (!m) throw NotFound('Message not found');
  const canDelete = m.authorId === user.id || ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
  if (!canDelete) throw Forbidden();
  return prisma.message.update({ where: { id }, data: { deletedAt: new Date(), body: null } });
}

async function react({ messageId, userId, emoji }) {
  return prisma.messageReaction.upsert({
    where: { messageId_userId_emoji: { messageId, userId, emoji } },
    update: {},
    create: { messageId, userId, emoji },
  });
}

async function unreact({ messageId, userId, emoji }) {
  await prisma.messageReaction
    .delete({ where: { messageId_userId_emoji: { messageId, userId, emoji } } })
    .catch(() => {});
}

async function pin({ messageId, value }) {
  return prisma.message.update({ where: { id: messageId }, data: { pinned: !!value } });
}

async function markRead({ channelId, userId }) {
  return prisma.channelMember.update({
    where: { channelId_userId: { channelId, userId } },
    data: { lastReadAt: new Date() },
  });
}

async function recordReceipt({ messageId, userId, state }) {
  const message = await prisma.message.findUnique({ where: { id: messageId } });
  if (!message || message.authorId === userId) return null;
  const receipt = await prisma.messageReceipt.upsert({
    where: { messageId_userId_state: { messageId, userId, state } },
    update: { at: new Date() },
    create: { messageId, userId, state },
  });
  return { ...receipt, message };
}

async function recordReceiptsBulk({ messageIds, userId, state }) {
  // Use createMany with skipDuplicates so we don't churn on already-seen messages.
  // We also need to filter out messages authored by the receiver themselves.
  const messages = await prisma.message.findMany({
    where: { id: { in: messageIds }, NOT: { authorId: userId } },
    select: { id: true },
  });
  const rows = messages.map((m) => ({ messageId: m.id, userId, state }));
  if (rows.length === 0) return { count: 0 };
  await prisma.messageReceipt.createMany({ data: rows, skipDuplicates: true });
  return { count: rows.length };
}

module.exports = {
  listMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  react,
  unreact,
  pin,
  markRead,
  recordReceipt,
  recordReceiptsBulk,
  listThread,
};
