'use strict';

const prisma = require('../../database/prisma');
const { hashPassword, sanitize } = require('../auth/auth.service');
const tenant = require('../../services/tenant');
const { NotFound, Conflict, Forbidden, BadRequest } = require('../../utils/errors');

async function list(req, { q, role, status, page = 1, pageSize = 25, forChat = false }) {
  const effectivePageSize = forChat ? Math.max(pageSize, 100) : pageSize;
  const where = tenant.scopedWhere(req, {
    isClient: false,
    ...(role
      ? { role }
      : forChat
        ? {
            role: {
              in: [
                'SUPER_ADMIN',
                'ADMIN',
                'MANAGER',
                'PROJECT_COORDINATOR_MANAGER',
                'EMPLOYEE',
                'TELECALLER',
              ],
            },
          }
        : { role: { not: 'SUPER_ADMIN' } }),
    ...(status ? { status } : forChat ? { status: 'ACTIVE' } : {}),
    ...(q
      ? {
          OR: [
            { userId: { contains: q, mode: 'insensitive' } },
            { name: { contains: q, mode: 'insensitive' } },
            { email: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
  });
  const [total, items] = await prisma.$transaction([
    prisma.user.count({ where }),
    prisma.user.findMany({
      where,
      orderBy: forChat ? { name: 'asc' } : { createdAt: 'desc' },
      skip: (page - 1) * effectivePageSize,
      take: effectivePageSize,
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
  return { total, page, pageSize: effectivePageSize, items: items.map(sanitize) };
}

async function getById(req, id) {
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
  if (tenant.MULTI_TENANT && u.tenantId !== tenant.resolveTenantId(req)) {
    throw NotFound('Employee not found');
  }
  return sanitize(u);
}

async function create(req, input, createdById) {
  const tenantId = tenant.resolveTenantId(req);
  await tenant.assertDepartmentInOrg(req, input.departmentId || null);
  const existing = await prisma.user.findUnique({
    where: { tenantId_userId: { tenantId, userId: input.userId } },
  });
  if (existing) throw Conflict('userId already in use in this organisation');

  const passwordHash = await hashPassword(input.password);
  const supervisorIds = Array.from(new Set((input.supervisorIds || []).filter(Boolean)));
  await tenant.filterUserIdsInTenant(req, supervisorIds);

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
        tenantId,
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

async function update(req, id, input) {
  await getById(req, id);
  if (input.departmentId !== undefined) {
    await tenant.assertDepartmentInOrg(req, input.departmentId || null);
  }
  const data = { ...input };
  if (input.password) data.passwordHash = await hashPassword(input.password);
  delete data.password;
  const supervisorIds = data.supervisorIds;
  delete data.supervisorIds;

  if (input.userId) {
    const tenantId = tenant.resolveTenantId(req);
    const clash = await prisma.user.findUnique({
      where: { tenantId_userId: { tenantId, userId: input.userId } },
    });
    if (clash && clash.id !== id) throw Conflict('userId already in use in this organisation');
  }

  if (Array.isArray(supervisorIds)) {
    await tenant.filterUserIdsInTenant(req, supervisorIds);
  }

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
    if (e.code === 'P2002') throw Conflict('userId already in use');
    throw e;
  }
}

async function setStatus(req, id, status) {
  return update(req, id, { status });
}

async function remove(req, id, actorId) {
  const user = await getById(req, id);

  try {
    await prisma.$transaction(async (tx) => {
      await tx.activityLog.updateMany({ where: { actorId: id }, data: { actorId: null } });
      await tx.lead.updateMany({ where: { ownerId: id }, data: { ownerId: null } });
      await tx.telecallerCall.deleteMany({ where: { agentId: id } });

      await tx.taskAssignee.deleteMany({ where: { userId: id } });
      await tx.taskReportRecipient.deleteMany({ where: { userId: id } });
      await tx.taskCompletionReport.deleteMany({ where: { authorId: id } });
      await tx.taskComment.deleteMany({ where: { authorId: id } });

      const taskIds = (
        await tx.task.findMany({ where: { createdById: id }, select: { id: true } })
      ).map((t) => t.id);
      if (taskIds.length) {
        await tx.task.deleteMany({ where: { id: { in: taskIds } } });
      }

      await tx.callParticipant.deleteMany({ where: { userId: id } });
      const callIds = (
        await tx.call.findMany({ where: { initiatorId: id }, select: { id: true } })
      ).map((c) => c.id);
      if (callIds.length) {
        await tx.call.deleteMany({ where: { id: { in: callIds } } });
      }

      await tx.savedItem.deleteMany({ where: { userId: id } });
      await tx.calendarAttendee.deleteMany({ where: { userId: id } });
      await tx.calendarEvent.deleteMany({ where: { ownerId: id } });
      await tx.announcement.deleteMany({ where: { authorId: id } });
      await tx.meetingRoomParticipant.deleteMany({ where: { userId: id } });
      const meetingRoomIds = (
        await tx.meetingRoom.findMany({ where: { hostId: id }, select: { id: true } })
      ).map((r) => r.id);
      if (meetingRoomIds.length) {
        await tx.meetingRoom.deleteMany({ where: { id: { in: meetingRoomIds } } });
      }

      if (actorId) {
        await tx.fileAsset.updateMany({
          where: { uploadedById: id },
          data: { uploadedById: actorId },
        });
      }

      await tx.fileDownload.deleteMany({ where: { userId: id } });
      await tx.fileGrant.deleteMany({ where: { userId: id } });
      await tx.permissionGrant.deleteMany({ where: { userId: id } });
      await tx.featureFlagAssignment.deleteMany({ where: { userId: id } });
      await tx.notificationPreference.deleteMany({ where: { userId: id } });
      await tx.dashboardWidget.deleteMany({ where: { userId: id } });
      await tx.trustedDevice.deleteMany({ where: { userId: id } });
      await tx.session.deleteMany({ where: { userId: id } });

      await tx.userSupervisor.deleteMany({
        where: { OR: [{ userId: id }, { supervisorId: id }] },
      });
      await tx.user.updateMany({
        where: { createdById: id },
        data: { createdById: actorId || null },
      });
      await tx.workdayLog.deleteMany({ where: { userId: id } });
      await tx.refreshToken.deleteMany({ where: { userId: id } });
      await tx.deviceToken.deleteMany({ where: { userId: id } });
      await tx.notification.deleteMany({ where: { userId: id } });
      await tx.channelMember.deleteMany({ where: { userId: id } });
      await tx.messageReaction.deleteMany({ where: { userId: id } });
      await tx.messageReceipt.deleteMany({ where: { userId: id } });
      await tx.message.deleteMany({ where: { authorId: id } });
      await tx.userPresence.deleteMany({ where: { userId: id } });

      if (actorId) {
        await tx.channel.updateMany({
          where: { createdById: id },
          data: { createdById: actorId },
        });
      }

      await tx.user.delete({ where: { id } });
    });
  } catch (e) {
    if (e.code === 'P2003') {
      throw BadRequest(
        'Cannot delete this employee yet — they still have linked records. Try suspending the account instead.',
      );
    }
    if (e.code === 'P2025') throw NotFound('Employee not found');
    throw e;
  }
}

module.exports = { list, getById, create, update, setStatus, remove };
