'use strict';

const prisma = require('../../database/prisma');
const { hashPassword, sanitize } = require('../auth/auth.service');
const tenant = require('../../services/tenant');
const { NotFound, Conflict, BadRequest } = require('../../utils/errors');

async function list(req, { q, status, page = 1, pageSize = 25 }) {
  const where = tenant.scopedWhere(req, {
    isClient: true,
    ...(status ? { status } : {}),
    ...(q
      ? {
          OR: [
            { userId: { contains: q, mode: 'insensitive' } },
            { name: { contains: q, mode: 'insensitive' } },
            { clientCompany: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
  });
  const [total, items] = await prisma.$transaction([
    prisma.user.count({ where }),
    prisma.user.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
  ]);
  return { total, page, pageSize, items: items.map(sanitize) };
}

async function getById(req, id) {
  const u = await prisma.user.findUnique({ where: { id } });
  if (!u || !u.isClient) throw NotFound('Client not found');
  if (tenant.MULTI_TENANT && u.tenantId !== tenant.resolveTenantId(req)) {
    throw NotFound('Client not found');
  }
  return sanitize(u);
}

async function create(req, input, createdById) {
  if (input.accessEndsAt && input.accessStartsAt && new Date(input.accessEndsAt) <= new Date(input.accessStartsAt)) {
    throw BadRequest('accessEndsAt must be after accessStartsAt');
  }
  const tenantId = tenant.resolveTenantId(req);
  const existing = await prisma.user.findUnique({
    where: { tenantId_userId: { tenantId, userId: input.userId } },
  });
  if (existing) throw Conflict('userId already in use in this organisation');

  const passwordHash = await hashPassword(input.password);
  const user = await prisma.user.create({
    data: {
      userId: input.userId,
      passwordHash,
      role: 'CLIENT',
      name: input.name,
      email: input.email || null,
      phone: input.phone || null,
      avatarUrl: input.avatarUrl || null,
      isClient: true,
      clientCompany: input.clientCompany || null,
      accessStartsAt: input.accessStartsAt ? new Date(input.accessStartsAt) : new Date(),
      accessEndsAt: input.accessEndsAt ? new Date(input.accessEndsAt) : null,
      tenantId,
      createdById,
    },
  });
  return sanitize(user);
}

async function update(req, id, input) {
  await getById(req, id);
  const data = { ...input };
  if (input.password) data.passwordHash = await hashPassword(input.password);
  delete data.password;
  if (data.accessStartsAt) data.accessStartsAt = new Date(data.accessStartsAt);
  if (data.accessEndsAt) data.accessEndsAt = new Date(data.accessEndsAt);
  try {
    const u = await prisma.user.update({ where: { id }, data });
    return sanitize(u);
  } catch (e) {
    if (e.code === 'P2025') throw NotFound('Client not found');
    throw e;
  }
}

async function extendAccess(req, id, untilIso) {
  const until = new Date(untilIso);
  if (Number.isNaN(until.getTime())) throw BadRequest('Invalid date');
  return update(req, id, { accessEndsAt: until, status: 'ACTIVE' });
}

async function disable(req, id) {
  return update(req, id, { status: 'SUSPENDED' });
}

/** Remove client channels so they disappear from every member's chat list. */
async function deleteClientChannels(tx, clientId, tenantId) {
  const channels = await tx.channel.findMany({
    where: {
      OR: [{ kind: 'CLIENT' }, { isClientChannel: true }],
      members: { some: { userId: clientId } },
      ...(tenantId ? { tenantId } : {}),
    },
    select: { id: true },
  });
  const channelIds = channels.map((c) => c.id);
  if (!channelIds.length) return;

  await tx.call.updateMany({
    where: { channelId: { in: channelIds } },
    data: { channelId: null },
  });
  await tx.announcement.updateMany({
    where: { channelId: { in: channelIds } },
    data: { channelId: null },
  });
  await tx.channel.deleteMany({ where: { id: { in: channelIds } } });
}

async function remove(req, id) {
  const client = await getById(req, id);
  const actorId = req.user?.id;
  const tenantId = client.tenantId || tenant.resolveTenantId(req);
  try {
    await prisma.$transaction(async (tx) => {
      await deleteClientChannels(tx, id, tenantId);
      await tx.activityLog.updateMany({ where: { actorId: id }, data: { actorId: null } });
      await tx.callParticipant.deleteMany({ where: { userId: id } });
      const callIds = (
        await tx.call.findMany({ where: { initiatorId: id }, select: { id: true } })
      ).map((c) => c.id);
      if (callIds.length) {
        await tx.call.deleteMany({ where: { id: { in: callIds } } });
      }
      await tx.savedItem.deleteMany({ where: { userId: id } });
      await tx.refreshToken.deleteMany({ where: { userId: id } });
      await tx.deviceToken.deleteMany({ where: { userId: id } });
      await tx.notification.deleteMany({ where: { userId: id } });
      await tx.messageReaction.deleteMany({ where: { userId: id } });
      await tx.messageReceipt.deleteMany({ where: { userId: id } });
      await tx.message.deleteMany({ where: { authorId: id } });
      await tx.channelMember.deleteMany({ where: { userId: id } });
      await tx.userPresence.deleteMany({ where: { userId: id } });
      if (actorId) {
        await tx.channel.updateMany({
          where: { createdById: id },
          data: { createdById: actorId },
        });
        await tx.user.updateMany({
          where: { createdById: id },
          data: { createdById: actorId },
        });
      }
      await tx.user.delete({ where: { id } });
    });
  } catch (e) {
    if (e.code === 'P2025') throw NotFound('Client not found');
    if (e.code === 'P2003') {
      throw BadRequest(
        'Cannot delete this client yet — they still have linked records. Try suspending instead.',
      );
    }
    throw e;
  }
}

module.exports = { list, getById, create, update, extendAccess, disable, remove };
