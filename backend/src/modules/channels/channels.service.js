'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const cache = require('../../services/cache');
const tenant = require('../../services/tenant');

const memberUserSelect = {
  id: true,
  userId: true,
  name: true,
  role: true,
  customTitle: true,
  avatarUrl: true,
  isClient: true,
  status: true,
  lastSeenAt: true,
};

async function withOnlineMembers(channel, viewer) {
  if (!channel?.members?.length) return channel;
  const viewerCanSeeAdminPresence = ['ADMIN', 'SUPER_ADMIN'].includes(viewer?.role);
  const members = await Promise.all(
    channel.members.map(async (member) => {
      if (!member.user) return member;
      const online = await cache.get(`presence:online:${member.user.id}`).catch(() => null);
      const hidePresence =
        !viewerCanSeeAdminPresence && ['ADMIN', 'SUPER_ADMIN'].includes(member.user.role);
      return {
        ...member,
        user: {
          ...member.user,
          online: hidePresence ? false : online === true,
          lastSeenAt: hidePresence ? null : member.user.lastSeenAt,
        },
      };
    })
  );
  return { ...channel, members };
}

async function ensureMember(channelId, userId) {
  const m = await prisma.channelMember.findUnique({
    where: { channelId_userId: { channelId, userId } },
  });
  if (!m) throw Forbidden('Not a member of this channel');
  return m;
}

/** Member, or org admin within the same tenant. */
async function assertChannelAccess(channelId, user) {
  const channel = await prisma.channel.findUnique({
    where: { id: channelId },
    select: { id: true, tenantId: true, kind: true },
  });
  if (!channel) throw NotFound('Channel not found');
  tenant.assertSameTenant(user, channel.tenantId);
  const member = await prisma.channelMember.findUnique({
    where: { channelId_userId: { channelId, userId: user.id } },
  });
  if (!member && !tenant.canAdministerTenant(user, channel.tenantId)) {
    throw Forbidden('Not a member of this channel');
  }
  if (user.isClient && channel.kind !== 'CLIENT') {
    throw Forbidden('Clients can only access client channels');
  }
  return channel;
}

async function listForUser(user) {
  // Clients only see channels they're explicitly added to
  const channels = await prisma.channel.findMany({
    where: {
      archived: false,
      members: { some: { userId: user.id } },
      ...(tenant.MULTI_TENANT ? { tenantId: tenant.userTenantId(user) } : {}),
      ...(user.isClient ? { kind: 'CLIENT' } : {}),
    },
    include: {
      members: { include: { user: { select: memberUserSelect } } },
      _count: { select: { messages: true } },
      // Most-recent non-deleted message per channel — the Flutter chat list
      // uses this for the WhatsApp-style preview line ("📷 Photo", body
      // text, "🎙️ Voice note", etc).
      messages: {
        where: { deletedAt: null },
        orderBy: { createdAt: 'desc' },
        take: 1,
        select: {
          id: true,
          body: true,
          kind: true,
          createdAt: true,
          authorId: true,
          author: { select: { id: true, name: true, avatarUrl: true, isClient: true } },
        },
      },
    },
    orderBy: [{ pinned: 'desc' }, { updatedAt: 'desc' }],
  });

  return Promise.all(
    channels.map(async (channel) => {
      const myMember = channel.members.find((member) => member.userId === user.id);
      const since = myMember?.lastReadAt || myMember?.joinedAt || new Date(0);
      const unreadCount = await prisma.message.count({
        where: {
          channelId: channel.id,
          deletedAt: null,
          authorId: { not: user.id },
          createdAt: { gt: since },
        },
      });
      const { messages, ...rest } = channel;
      return withOnlineMembers({ ...rest, lastMessage: messages[0] || null, unreadCount }, user);
    })
  ).then((items) =>
    items.filter((channel) => {
      if (channel.kind !== 'DM') return true;
      const others = channel.members.filter((m) => m.userId !== user.id && m.user);
      return others.some((m) => {
        const name = (m.user.name || '').trim();
        const loginId = (m.user.userId || '').trim();
        return name.length > 0 || loginId.length > 0;
      });
    })
  );
}

async function directoryForUser(user, q = '') {
  const base = tenant.tenantClause(user, {
    status: 'ACTIVE',
    ...(user.isClient ? { isClient: false } : {}),
    ...(q
      ? {
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { userId: { contains: q, mode: 'insensitive' } },
            { customTitle: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
  });

  return prisma.user.findMany({
    where: base,
    orderBy: { name: 'asc' },
    take: 30,
    select: {
      id: true,
      userId: true,
      name: true,
      role: true,
      customTitle: true,
      avatarUrl: true,
      isClient: true,
      status: true,
    },
  });
}

async function create(input, creator) {
  if (creator.isClient) {
    throw Forbidden('Clients cannot create channels');
  }

  if (input.kind === 'DM') {
    if (!input.memberIds || input.memberIds.length !== 1) {
      throw BadRequest('DM requires exactly one other member');
    }

    const otherId = input.memberIds[0];
    const existingDm = await prisma.channel.findFirst({
      where: {
        kind: 'DM',
        archived: false,
        AND: [
          { members: { some: { userId: creator.id } } },
          { members: { some: { userId: otherId } } },
          { members: { none: { userId: { notIn: [creator.id, otherId] } } } },
        ],
      },
      include: { members: true },
    });

    if (existingDm) return existingDm;
  }

  const requestedIds = Array.from(new Set(input.memberIds || []));
  let memberIds = Array.from(new Set([creator.id, ...requestedIds]));

  if (input.kind === 'CLIENT') {
    if (!['SUPER_ADMIN', 'ADMIN'].includes(creator.role)) {
      throw Forbidden('Only admins can create client channels');
    }

    const selectedUsers = await prisma.user.findMany({
      where: tenant.tenantClause(creator, { id: { in: requestedIds }, status: 'ACTIVE' }),
      select: { id: true, isClient: true },
    });
    if (!selectedUsers.some((user) => user.isClient)) {
      throw BadRequest('Client channel requires at least one client');
    }

    const internalUsers = await prisma.user.findMany({
      where: {
        isClient: false,
        status: 'ACTIVE',
        tenantId: creator.tenantId,
      },
      select: { id: true },
    });
    memberIds = Array.from(new Set([
      creator.id,
      ...selectedUsers.map((user) => user.id),
      ...internalUsers.map((user) => user.id),
    ]));
  }

  const members = await prisma.user.findMany({
    where: {
      id: { in: memberIds },
      tenantId: creator.tenantId,
    },
  });
  if (members.length !== memberIds.length) {
    throw BadRequest('All members must belong to your organisation');
  }
  const hasClient = members.some((m) => m.isClient);

  if (hasClient && input.kind !== 'CLIENT') {
    throw BadRequest('Channels with clients must use CLIENT kind');
  }

  const channel = await prisma.channel.create({
    data: {
      name: input.name,
      description: input.description || null,
      kind: input.kind,
      visibility: input.visibility || 'PRIVATE',
      isClientChannel: hasClient || input.kind === 'CLIENT',
      createdById: creator.id,
      tenantId: creator.tenantId,
      members: {
        create: members.map((m) => ({
          userId: m.id,
          role: m.id === creator.id ? 'owner' : 'member',
        })),
      },
    },
    include: { members: true },
  });

  return channel;
}

async function getById(id, user) {
  const channel = await prisma.channel.findUnique({
    where: { id },
    include: {
      members: { include: { user: { select: memberUserSelect } } },
    },
  });
  if (!channel) throw NotFound('Channel not found');
  tenant.assertSameTenant(user, channel.tenantId);
  const isMember = channel.members.some((m) => m.userId === user.id);
  if (!isMember && !tenant.canAdministerTenant(user, channel.tenantId)) {
    throw Forbidden('Not a member of this channel');
  }
  return withOnlineMembers(channel, user);
}

async function addMembers(channelId, memberIds, actor) {
  const channel = await prisma.channel.findUnique({ where: { id: channelId }, include: { members: true } });
  if (!channel) throw NotFound('Channel not found');
  tenant.assertSameTenant(actor, channel.tenantId);

  const isOwner = channel.members.some((m) => m.userId === actor.id && (m.role === 'owner' || m.role === 'admin'));
  if (!isOwner && !tenant.canAdministerTenant(actor, channel.tenantId)) throw Forbidden('Not allowed');

  const newMembers = await prisma.user.findMany({
    where: tenant.tenantClause(actor, { id: { in: memberIds } }),
  });
  const includesClient = newMembers.some((u) => u.isClient);

  await prisma.$transaction([
    ...newMembers.map((u) =>
      prisma.channelMember.upsert({
        where: { channelId_userId: { channelId, userId: u.id } },
        update: {},
        create: { channelId, userId: u.id, role: 'member' },
      })
    ),
    ...(includesClient && !channel.isClientChannel
      ? [prisma.channel.update({ where: { id: channelId }, data: { isClientChannel: true } })]
      : []),
  ]);

  return getById(channelId, actor);
}

async function removeMember(channelId, memberId, actor) {
  const channel = await prisma.channel.findUnique({ where: { id: channelId }, select: { tenantId: true } });
  if (!channel) throw NotFound('Channel not found');
  tenant.assertSameTenant(actor, channel.tenantId);
  await ensureMember(channelId, actor.id).catch(() => {
    if (!tenant.canAdministerTenant(actor, channel.tenantId)) throw Forbidden();
  });
  await prisma.channelMember.delete({
    where: { channelId_userId: { channelId, userId: memberId } },
  }).catch(() => {});
  return getById(channelId, actor);
}

async function pin(id, value) {
  return prisma.channel.update({ where: { id }, data: { pinned: !!value } });
}

async function archive(id, value) {
  return prisma.channel.update({ where: { id }, data: { archived: !!value } });
}

async function setPolicy(id, policy, actor) {
  const channel = await prisma.channel.findUnique({ where: { id }, select: { tenantId: true } });
  if (!channel) throw NotFound('Channel not found');
  tenant.assertSameTenant(actor, channel.tenantId);
  if (!tenant.canAdministerTenant(actor, channel.tenantId)) {
    const m = await prisma.channelMember.findUnique({
      where: { channelId_userId: { channelId: id, userId: actor.id } },
    });
    if (!m || !['OWNER', 'ADMIN'].includes(m.memberRole)) throw Forbidden();
  }
  return prisma.channel.update({ where: { id }, data: policy });
}

async function setMemberPermissions(channelId, userId, perms, actor) {
  const channel = await prisma.channel.findUnique({ where: { id: channelId }, select: { tenantId: true } });
  if (!channel) throw NotFound('Channel not found');
  tenant.assertSameTenant(actor, channel.tenantId);
  if (!tenant.canAdministerTenant(actor, channel.tenantId)) {
    const m = await prisma.channelMember.findUnique({
      where: { channelId_userId: { channelId, userId: actor.id } },
    });
    if (!m || !['OWNER', 'ADMIN'].includes(m.memberRole)) throw Forbidden();
  }
  return prisma.channelMember.update({
    where: { channelId_userId: { channelId, userId } },
    data: perms,
  });
}

module.exports = {
  ensureMember,
  assertChannelAccess,
  listForUser,
  directoryForUser,
  create,
  getById,
  addMembers,
  removeMember,
  pin,
  archive,
  setPolicy,
  setMemberPermissions,
};
