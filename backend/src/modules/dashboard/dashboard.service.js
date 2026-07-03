'use strict';

const prisma = require('../../database/prisma');
const dayjs = require('dayjs');
const tenant = require('../../services/tenant');

async function adminOverview(user) {
  const since = dayjs().subtract(7, 'day').toDate();
  const orgUsers = tenant.tenantClause(user, {});
  const orgTasks = tenant.tenantClause(user, {});
  const orgCalls = tenant.tenantClause(user, {});
  const orgLeads = tenant.tenantClause(user, {});

  const [
    employees,
    clients,
    activeClients,
    expiredClients,
    tasksOpen,
    tasksDoneThisWeek,
    leadsTotal,
    callsToday,
    activeCalls,
    recentActivity,
  ] = await prisma.$transaction([
    prisma.user.count({ where: { isClient: false, ...orgUsers } }),
    prisma.user.count({ where: { isClient: true, ...orgUsers } }),
    prisma.user.count({ where: { isClient: true, status: 'ACTIVE', ...orgUsers } }),
    prisma.user.count({ where: { isClient: true, status: 'EXPIRED', ...orgUsers } }),
    prisma.task.count({
      where: { status: { in: ['BACKLOG', 'TODO', 'IN_PROGRESS', 'REVIEW'] }, ...orgTasks },
    }),
    prisma.task.count({
      where: { status: 'DONE', updatedAt: { gte: since }, ...orgTasks },
    }),
    prisma.lead.count({ where: orgLeads }),
    prisma.telecallerCall.count({
      where: {
        createdAt: { gte: dayjs().startOf('day').toDate() },
        ...(tenant.MULTI_TENANT
          ? { lead: { tenantId: tenant.userTenantId(user) } }
          : {}),
      },
    }),
    prisma.call.count({
      where: { status: { in: ['RINGING', 'ACTIVE'] }, ...orgCalls },
    }),
    prisma.activityLog.findMany({
      where: tenant.MULTI_TENANT
        ? { actor: { tenantId: tenant.userTenantId(user) } }
        : {},
      orderBy: { createdAt: 'desc' },
      take: 20,
      include: { actor: { select: { id: true, name: true, role: true, avatarUrl: true, isClient: true } } },
    }),
  ]);

  return {
    counts: {
      employees,
      clients,
      activeClients,
      expiredClients,
      tasksOpen,
      tasksDoneThisWeek,
      leadsTotal,
      callsToday,
      activeCalls,
    },
    recentActivity,
  };
}

async function employeeOverview(user) {
  const [myOpenTasks, myDoneThisWeek, unreadNotifs, activeChannels] = await prisma.$transaction([
    prisma.task.count({
      where: {
        status: { in: ['TODO', 'IN_PROGRESS', 'REVIEW'] },
        assignees: { some: { userId: user.id } },
      },
    }),
    prisma.task.count({
      where: {
        status: 'DONE',
        assignees: { some: { userId: user.id } },
        updatedAt: { gte: dayjs().subtract(7, 'day').toDate() },
      },
    }),
    prisma.notification.count({ where: { userId: user.id, readAt: null } }),
    prisma.channelMember.count({ where: { userId: user.id } }),
  ]);

  return {
    counts: { myOpenTasks, myDoneThisWeek, unreadNotifs, activeChannels },
  };
}

async function clientOverview(user) {
  const [channels, unreadNotifs] = await prisma.$transaction([
    prisma.channel.findMany({
      where: { members: { some: { userId: user.id } } },
      include: { _count: { select: { messages: true } } },
    }),
    prisma.notification.count({ where: { userId: user.id, readAt: null } }),
  ]);
  return {
    counts: {
      channels: channels.length,
      unreadNotifs,
      accessEndsAt: user.accessEndsAt,
    },
    channels,
  };
}

module.exports = { adminOverview, employeeOverview, clientOverview };
