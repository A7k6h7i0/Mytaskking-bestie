'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');

async function ensureMember(channelId, userId) {
  const m = await prisma.channelMember.findUnique({
    where: { channelId_userId: { channelId, userId } },
  });
  if (!m) throw Forbidden('Not a member of this channel');
  return m;
}

async function listForUser(user) {
  // Clients only see channels they're explicitly added to
  const channels = await prisma.channel.findMany({
    where: {
      archived: false,
      members: { some: { userId: user.id } },
      ...(user.isClient ? { kind: 'CLIENT' } : {}),
    },
    include: {
      members: { include: { user: { select: { id: true, userId: true, name: true, role: true, customTitle: true, avatarUrl: true, isClient: true } } } },
      _count: { select: { messages: true } },
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
      return { ...channel, unreadCount };
    })
  );
}

async function directoryForUser(user, q = '') {
  const where = user.isClient
    ? {
        isClient: false,
        status: 'ACTIVE',
        ...(q
          ? {
              OR: [
                { name: { contains: q, mode: 'insensitive' } },
                { userId: { contains: q, mode: 'insensitive' } },
                { customTitle: { contains: q, mode: 'insensitive' } },
              ],
            }
          : {}),
      }
    : {
        status: 'ACTIVE',
        ...(q
          ? {
              OR: [
                { name: { contains: q, mode: 'insensitive' } },
                { userId: { contains: q, mode: 'insensitive' } },
                { customTitle: { contains: q, mode: 'insensitive' } },
              ],
            }
          : {}),
      };

  return prisma.user.findMany({
    where,
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
  if (input.kind === 'DM') {
    if (creator.isClient) throw Forbidden('Clients cannot start direct messages');
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
  const memberIds = Array.from(new Set([creator.id, ...(input.memberIds || [])]));
  const members = await prisma.user.findMany({ where: { id: { in: memberIds } } });
  const hasClient = members.some((m) => m.isClient);

  if (creator.isClient && input.kind !== 'CLIENT') {
    throw Forbidden('Clients can only create client channels');
  }
  if (!creator.isClient && input.kind === 'CLIENT') {
    throw Forbidden('Only clients can create client channels');
  }

  const channel = await prisma.channel.create({
    data: {
      name: input.name,
      description: input.description || null,
      kind: input.kind,
      visibility: input.visibility || 'PRIVATE',
      isClientChannel: hasClient || input.kind === 'CLIENT',
      createdById: creator.id,
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
      members: { include: { user: { select: { id: true, userId: true, name: true, role: true, customTitle: true, avatarUrl: true, isClient: true } } } },
    },
  });
  if (!channel) throw NotFound('Channel not found');
  if (!channel.members.some((m) => m.userId === user.id) && !['SUPER_ADMIN', 'ADMIN'].includes(user.role)) {
    throw Forbidden('Not a member of this channel');
  }
  return channel;
}

async function addMembers(channelId, memberIds, actor) {
  const channel = await prisma.channel.findUnique({ where: { id: channelId }, include: { members: true } });
  if (!channel) throw NotFound('Channel not found');

  const isOwner = channel.members.some((m) => m.userId === actor.id && (m.role === 'owner' || m.role === 'admin'));
  if (!isOwner && !['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) throw Forbidden('Not allowed');

  const newMembers = await prisma.user.findMany({ where: { id: { in: memberIds } } });
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
  await ensureMember(channelId, actor.id).catch(() => {
    if (!['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) throw Forbidden();
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
  if (!['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
    const m = await prisma.channelMember.findUnique({
      where: { channelId_userId: { channelId: id, userId: actor.id } },
    });
    if (!m || !['OWNER', 'ADMIN'].includes(m.memberRole)) throw Forbidden();
  }
  return prisma.channel.update({ where: { id }, data: policy });
}

async function setMemberPermissions(channelId, userId, perms, actor) {
  if (!['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
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
