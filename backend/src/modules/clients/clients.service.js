'use strict';

const prisma = require('../../database/prisma');
const { hashPassword, sanitize } = require('../auth/auth.service');
const { NotFound, Conflict, BadRequest } = require('../../utils/errors');

async function list({ q, status, page = 1, pageSize = 25 }) {
  const where = {
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
  };
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

async function getById(id) {
  const u = await prisma.user.findUnique({ where: { id } });
  if (!u || !u.isClient) throw NotFound('Client not found');
  return sanitize(u);
}

async function create(input, createdById) {
  if (input.accessEndsAt && input.accessStartsAt && new Date(input.accessEndsAt) <= new Date(input.accessStartsAt)) {
    throw BadRequest('accessEndsAt must be after accessStartsAt');
  }
  const existing = await prisma.user.findUnique({ where: { userId: input.userId } });
  if (existing) throw Conflict('userId already in use');

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
      createdById,
    },
  });
  return sanitize(user);
}

async function update(id, input) {
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

async function extendAccess(id, untilIso) {
  const until = new Date(untilIso);
  if (Number.isNaN(until.getTime())) throw BadRequest('Invalid date');
  return update(id, { accessEndsAt: until, status: 'ACTIVE' });
}

async function disable(id) {
  return update(id, { status: 'SUSPENDED' });
}

async function remove(id) {
  try {
    await prisma.user.delete({ where: { id } });
  } catch (e) {
    if (e.code === 'P2025') throw NotFound('Client not found');
    throw e;
  }
}

module.exports = { list, getById, create, update, extendAccess, disable, remove };
