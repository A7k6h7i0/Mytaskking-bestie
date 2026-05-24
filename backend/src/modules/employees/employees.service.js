'use strict';

const prisma = require('../../database/prisma');
const { hashPassword, sanitize } = require('../auth/auth.service');
const { NotFound, Conflict } = require('../../utils/errors');

async function list({ q, role, status, page = 1, pageSize = 25 }) {
  const where = {
    isClient: false,
    ...(role ? { role } : { role: { not: 'SUPER_ADMIN' } }),
    ...(status ? { status } : {}),
    ...(q
      ? {
          OR: [
            { userId: { contains: q, mode: 'insensitive' } },
            { name: { contains: q, mode: 'insensitive' } },
            { email: { contains: q, mode: 'insensitive' } },
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
      include: {
        department: true,
        supervisors: {
          include: {
            supervisor: {
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
            },
          },
        },
      },
    }),
  ]);
  return { total, page, pageSize, items: items.map(sanitize) };
}

async function getById(id) {
  const u = await prisma.user.findUnique({
    where: { id },
    include: {
      department: true,
      supervisors: {
        include: {
          supervisor: {
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
          },
        },
      },
    },
  });
  if (!u || u.isClient || u.role === 'SUPER_ADMIN') throw NotFound('Employee not found');
  return sanitize(u);
}

async function create(input, createdById) {
  const existing = await prisma.user.findUnique({ where: { userId: input.userId } });
  if (existing) throw Conflict('userId already in use');

  const passwordHash = await hashPassword(input.password);
  const supervisorIds = Array.from(new Set((input.supervisorIds || []).filter(Boolean)));
  const user = await prisma.$transaction(async (tx) => {
    const created = await tx.user.create({
      data: {
        userId: input.userId,
        passwordHash,
        role: input.role,
        customTitle: input.customTitle || null,
        name: input.name,
        email: input.email || null,
        phone: input.phone || null,
        avatarUrl: input.avatarUrl || null,
        departmentId: input.departmentId || null,
        isClient: false,
        createdById,
      },
    });
    if (supervisorIds.length) {
      await tx.userSupervisor.createMany({
        data: supervisorIds
          .filter((supervisorId) => supervisorId !== created.id)
          .map((supervisorId) => ({ userId: created.id, supervisorId })),
        skipDuplicates: true,
      });
    }
      return tx.user.findUnique({
        where: { id: created.id },
        include: {
          department: true,
          supervisors: {
            include: {
              supervisor: {
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
              },
            },
          },
        },
      });
  });
  return sanitize(user);
}

async function update(id, input) {
  const data = { ...input };
  if (input.password) data.passwordHash = await hashPassword(input.password);
  delete data.password;
  const supervisorIds = data.supervisorIds;
  delete data.supervisorIds;
  try {
    const user = await prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id }, data });
      if (Array.isArray(supervisorIds)) {
        await tx.userSupervisor.deleteMany({ where: { userId: id } });
        if (supervisorIds.length) {
          await tx.userSupervisor.createMany({
            data: Array.from(new Set(supervisorIds))
              .filter((supervisorId) => supervisorId && supervisorId !== id)
              .map((supervisorId) => ({ userId: id, supervisorId })),
            skipDuplicates: true,
          });
        }
      }
      return tx.user.findUnique({
        where: { id },
        include: {
          department: true,
          supervisors: {
            include: {
              supervisor: {
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
              },
            },
          },
        },
      });
    });
    return sanitize(user);
  } catch (e) {
    if (e.code === 'P2025') throw NotFound('Employee not found');
    throw e;
  }
}

async function setStatus(id, status) {
  return update(id, { status });
}

async function remove(id) {
  try {
    await prisma.user.delete({ where: { id } });
  } catch (e) {
    if (e.code === 'P2025') throw NotFound('Employee not found');
    throw e;
  }
}

module.exports = { list, getById, create, update, setStatus, remove };
