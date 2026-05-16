'use strict';

const prisma = require('../../database/prisma');

/**
 * Postgres-backed search adapter — case-insensitive contains + a small
 * recent-activity boost. Same in-place implementation as the previous
 * `/search` route, just packaged as an adapter so larger engines can replace
 * it.
 */

async function search({ user, q, kinds, perEntity = 6, recentBoost = true }) {
  const isClient = user.isClient;
  const isAdmin = ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
  const wants = (k) => !kinds || kinds.includes(k);

  const myChannelIds = await prisma.channelMember
    .findMany({ where: { userId: user.id }, select: { channelId: true } })
    .then((rows) => rows.map((r) => r.channelId));

  const tasks = [];

  if (wants('users') && !isClient) {
    tasks.push(
      prisma.user
        .findMany({
          where: {
            OR: [
              { userId: { contains: q, mode: 'insensitive' } },
              { name: { contains: q, mode: 'insensitive' } },
              { email: { contains: q, mode: 'insensitive' } },
            ],
          },
          orderBy: recentBoost ? { lastSeenAt: 'desc' } : { createdAt: 'desc' },
          take: perEntity,
          select: { id: true, userId: true, name: true, role: true, isClient: true, avatarUrl: true, clientCompany: true },
        })
        .then((items) => ['users', items])
    );
  }

  if (wants('channels')) {
    tasks.push(
      prisma.channel
        .findMany({
          where: {
            archived: false,
            ...(isAdmin ? {} : { id: { in: myChannelIds } }),
            OR: [
              { name: { contains: q, mode: 'insensitive' } },
              { description: { contains: q, mode: 'insensitive' } },
            ],
          },
          orderBy: recentBoost ? { updatedAt: 'desc' } : { createdAt: 'desc' },
          take: perEntity,
          select: { id: true, name: true, kind: true, isClientChannel: true, updatedAt: true },
        })
        .then((items) => ['channels', items])
    );
  }

  if (wants('tasks')) {
    tasks.push(
      prisma.task
        .findMany({
          where: {
            OR: [
              { title: { contains: q, mode: 'insensitive' } },
              { description: { contains: q, mode: 'insensitive' } },
            ],
            ...(!isAdmin
              ? {
                  OR: [
                    { createdById: user.id },
                    { assignees: { some: { userId: user.id } } },
                  ],
                }
              : {}),
          },
          orderBy: { updatedAt: 'desc' },
          take: perEntity,
          select: { id: true, title: true, status: true, priority: true, dueAt: true, updatedAt: true },
        })
        .then((items) => ['tasks', items])
    );
  }

  if (wants('messages')) {
    tasks.push(
      prisma.message
        .findMany({
          where: {
            deletedAt: null,
            body: { contains: q, mode: 'insensitive' },
            ...(isAdmin ? {} : { channelId: { in: myChannelIds } }),
          },
          orderBy: { createdAt: 'desc' },
          take: perEntity,
          include: {
            author: { select: { id: true, name: true, avatarUrl: true, isClient: true, role: true } },
            channel: { select: { id: true, name: true, kind: true, isClientChannel: true } },
          },
        })
        .then((items) => ['messages', items])
    );
  }

  if (wants('files')) {
    tasks.push(
      prisma.fileAsset
        .findMany({
          where: {
            ...(!isAdmin ? { uploadedById: user.id } : {}),
            OR: [
              { originalName: { contains: q, mode: 'insensitive' } },
              { category: { contains: q, mode: 'insensitive' } },
            ],
          },
          orderBy: { createdAt: 'desc' },
          take: perEntity,
          select: {
            id: true, url: true, originalName: true, mimeType: true,
            size: true, backend: true, createdAt: true,
          },
        })
        .then((items) => ['files', items])
    );
  }

  if (wants('leads') && !isClient) {
    tasks.push(
      prisma.lead
        .findMany({
          where: {
            ...(user.role === 'TELECALLER' ? { ownerId: user.id } : {}),
            OR: [
              { name: { contains: q, mode: 'insensitive' } },
              { phone: { contains: q } },
              { company: { contains: q, mode: 'insensitive' } },
            ],
          },
          orderBy: { updatedAt: 'desc' },
          take: perEntity,
          select: { id: true, name: true, phone: true, company: true, status: true },
        })
        .then((items) => ['leads', items])
    );
  }

  return { results: Object.fromEntries(await Promise.all(tasks)) };
}

async function index() { /* postgres adapter — nothing to do, we query live */ }
async function deindex() { /* postgres adapter — nothing to do, we query live */ }

module.exports = { search, index, deindex };
