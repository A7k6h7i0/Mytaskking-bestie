'use strict';

const prisma = require('../../database/prisma');
const dayjs = require('dayjs');

async function adminOverview() {
  const since = dayjs().subtract(7, 'day').toDate();

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
    prisma.user.count({ where: { isClient: false } }),
    prisma.user.count({ where: { isClient: true } }),
    prisma.user.count({ where: { isClient: true, status: 'ACTIVE' } }),
    prisma.user.count({ where: { isClient: true, status: 'EXPIRED' } }),
    prisma.task.count({ where: { status: { in: ['BACKLOG', 'TODO', 'IN_PROGRESS', 'REVIEW'] } } }),
    prisma.task.count({ where: { status: 'DONE', updatedAt: { gte: since } } }),
    prisma.lead.count(),
    prisma.telecallerCall.count({ where: { createdAt: { gte: dayjs().startOf('day').toDate() } } }),
    prisma.call.count({ where: { status: { in: ['RINGING', 'ACTIVE'] } } }),
    prisma.activityLog.findMany({ orderBy: { createdAt: 'desc' }, take: 20, include: { actor: { select: { id: true, name: true, role: true, avatarUrl: true, isClient: true } } } }),
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
