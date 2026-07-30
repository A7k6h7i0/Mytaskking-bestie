'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const channelsService = require('../channels/channels.service');
const notifications = require('../notifications/notifications.service');
const cache = require('../../services/cache');

const messageInclude = {
  author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true, customTitle: true } },
  attachments: true,
  reactions: true,
  replyTo: {
    select: {
      id: true,
      body: true,
      authorId: true,
      author: { select: { id: true, name: true } },
    },
  },
  receipts: { select: { userId: true, state: true, at: true } },
};

async function listMessages(channelId, user, { cursor, limit = 40 } = {}) {
  const channel = await channelsService.assertChannelAccess(channelId, user);

  const messages = await prisma.message.findMany({
    where: { channelId, deletedAt: null, ...(cursor ? { id: { lt: cursor } } : {}) },
    take: Math.min(limit, 100),
    orderBy: { id: 'desc' },
    include: messageInclude,
  });
  return { items: messages.reverse(), nextCursor: messages.length ? messages[0].id : null };
}

/** Channel kinds that should notify members on every new message (not just @mentions). */
const CHAT_NOTIFY_KINDS = new Set(['DM', 'GROUP', 'PROJECT', 'CLIENT']);

/**
 * Recompute aggregate Message.status from per-member receipts.
 * DM: one recipient — first SEEN turns ticks blue.
 * Group / project / client: SEEN only when every non-author member has SEEN;
 * DELIVERED only when every non-author member has at least DELIVERED (or SEEN).
 */
async function recomputeMessageStatus(messageId) {
  const message = await prisma.message.findUnique({
    where: { id: messageId },
    select: {
      id: true,
      authorId: true,
      status: true,
      channel: {
        select: {
          kind: true,
          members: { select: { userId: true } },
        },
      },
      receipts: { select: { userId: true, state: true } },
    },
  });
  if (!message) return null;

  const recipients = message.channel.members
    .map((m) => m.userId)
    .filter((id) => id !== message.authorId);
  if (!recipients.length) return message.status;

  const seenUsers = new Set(
    message.receipts.filter((r) => r.state === 'SEEN').map((r) => r.userId)
  );
  const deliveredUsers = new Set(
    message.receipts.filter((r) => r.state === 'DELIVERED').map((r) => r.userId)
  );
  const effectivelyDelivered = (userId) =>
    deliveredUsers.has(userId) || seenUsers.has(userId);

  let status = 'SENT';
  const allSeen = recipients.every((id) => seenUsers.has(id));
  const allDelivered = recipients.every((id) => effectivelyDelivered(id));
  if (allSeen) status = 'SEEN';
  else if (allDelivered) status = 'DELIVERED';

  if (status !== message.status) {
    await prisma.message.update({ where: { id: messageId }, data: { status } });
  }
  return status;
}

async function sendMessage({ channelId, user, body, kind = 'TEXT', attachmentIds = [], replyToId = null, threadRootId = null, io = null }) {
  await channelsService.assertChannelAccess(channelId, user);
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

  let message = await prisma.message.create({
    data: {
      channelId,
      authorId: user.id,
      body: body || null,
      kind,
      replyToId: replyToId || null,
      threadRootId: resolvedRootId || null,
      ...(attachmentIds.length ? { attachments: { connect: attachmentIds.map((id) => ({ id })) } } : {}),
    },
    include: messageInclude,
  });

  const onlineRecipientIds = await onlineMembersForDelivery(channel.members, user.id);
  if (onlineRecipientIds.length) {
    await prisma.messageReceipt.createMany({
      data: onlineRecipientIds.map((userId) => ({
        messageId: message.id,
        userId,
        state: 'DELIVERED',
      })),
      skipDuplicates: true,
    });
    const status = await recomputeMessageStatus(message.id);
    if (status) {
      message = await prisma.message.findUnique({
        where: { id: message.id },
        include: messageInclude,
      });
    }
  }

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
        io,
      }).catch(() => {})
    )
  );

  if (CHAT_NOTIFY_KINDS.has(channel.kind)) {
    const mentionedIds = new Set(mentionTargets.map((target) => target.id));
    const recipients = channel.members
      .map((member) => member.user)
      .filter((member) => member && member.id !== user.id && !mentionedIds.has(member.id));
    if (recipients.length) {
      const preview = body || (attachmentIds.length ? 'Sent an attachment' : 'New message');
      const title =
        channel.kind === 'DM'
          ? `New message from ${user.name}`
          : channel.name
            ? `New message in #${channel.name}`
            : `New message from ${user.name}`;

      await Promise.all(
        recipients.map((recipient) =>
          notifications.notify({
            userId: recipient.id,
            kind: 'CHAT',
            title,
            body: preview,
            data: { channelId, messageId: message.id, authorId: user.id },
            io,
          }).catch(() => {})
        )
      );
    }
  }

  return message;
}

const { findMentionTargets } = require('../../utils/mentions');

async function listThread({ rootId, user, limit = 100 }) {
  const root = await prisma.message.findUnique({
    where: { id: rootId },
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true, customTitle: true } },
      attachments: true,
      reactions: true,
    },
  });
  if (!root) throw NotFound('Thread not found');
  await channelsService.assertChannelAccess(root.channelId, user);

  const replies = await prisma.message.findMany({
    where: { threadRootId: rootId, deletedAt: null },
    orderBy: { createdAt: 'asc' },
    take: limit,
    include: {
      author: { select: { id: true, name: true, avatarUrl: true, role: true, isClient: true, customTitle: true } },
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
  const m = await prisma.message.findUnique({
    where: { id },
    include: { channel: { select: { tenantId: true } } },
  });
  if (!m) throw NotFound('Message not found');
  const tenant = require('../../services/tenant');
  const canDelete =
    m.authorId === user.id ||
    tenant.canAdministerTenant(user, m.channel?.tenantId);
  if (!canDelete) throw Forbidden();
  return prisma.message.update({ where: { id }, data: { deletedAt: new Date() } });
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
  const status = await recomputeMessageStatus(messageId);
  return { ...receipt, message, status };
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
  const statuses = {};
  await Promise.all(
    rows.map(async (r) => {
      statuses[r.messageId] = await recomputeMessageStatus(r.messageId);
    })
  );
  return { count: rows.length, statuses };
}

async function onlineMembersForDelivery(members, authorId) {
  const ids = [];
  for (const member of members || []) {
    const userId = member.userId || member.user?.id;
    if (!userId || userId === authorId) continue;
    const online = await cache.get(`presence:online:${userId}`).catch(() => null);
    if (online === true) ids.push(userId);
  }
  return ids;
}

async function markDeliveredForUser({ userId, channelIds, limit = 500 }) {
  const safeChannelIds = Array.from(new Set(channelIds || [])).filter(Boolean);
  if (!safeChannelIds.length) return [];
  const messages = await prisma.message.findMany({
    where: {
      channelId: { in: safeChannelIds },
      authorId: { not: userId },
      deletedAt: null,
      receipts: {
        none: {
          userId,
          state: 'DELIVERED',
        },
      },
    },
    orderBy: { createdAt: 'desc' },
    take: limit,
    select: { id: true, channelId: true },
  });
  if (!messages.length) return [];

  await prisma.messageReceipt.createMany({
    data: messages.map((message) => ({
      messageId: message.id,
      userId,
      state: 'DELIVERED',
    })),
    skipDuplicates: true,
  });

  const statuses = {};
  await Promise.all(
    messages.map(async (message) => {
      statuses[message.id] = await recomputeMessageStatus(message.id);
    })
  );

  const grouped = new Map();
  for (const message of messages) {
    const ids = grouped.get(message.channelId) || [];
    ids.push(message.id);
    grouped.set(message.channelId, ids);
  }
  return Array.from(grouped.entries()).map(([channelId, messageIds]) => ({
    channelId,
    messageIds,
    statuses: Object.fromEntries(messageIds.map((id) => [id, statuses[id]])),
  }));
}

async function listDeletedMessages({ user, page = 1, pageSize = 50, tenantId }) {
  const tenant = require('../../services/tenant');
  
  let targetTenantId = tenant.userTenantId(user);
  const isPlatformAdmin = tenant.isPlatformSuperAdmin(user);

  if (isPlatformAdmin) {
    if (tenantId) {
      targetTenantId = tenantId;
    } else {
      targetTenantId = null;
    }
  }

  const where = {
    deletedAt: { not: null },
    ...(targetTenantId ? { channel: { tenantId: targetTenantId } } : {}),
  };

  const [total, items] = await prisma.$transaction([
    prisma.message.count({ where }),
    prisma.message.findMany({
      where,
      orderBy: { deletedAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: {
        author: { select: { id: true, name: true, userId: true, role: true, avatarUrl: true, isClient: true } },
        channel: {
          select: {
            id: true,
            name: true,
            kind: true,
            tenantId: true,
            members: {
              select: {
                user: { select: { id: true, name: true, userId: true, role: true, avatarUrl: true, isClient: true } },
              },
            },
          },
        },
        attachments: true,
      },
    }),
  ]);

  return { total, page, pageSize, items };
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
  markDeliveredForUser,
  listThread,
  listDeletedMessages,
};
