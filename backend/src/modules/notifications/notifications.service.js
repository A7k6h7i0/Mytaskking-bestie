'use strict';

const prisma = require('../../database/prisma');
const fcm = require('../../services/fcm');

async function registerDevice({ userId, token, platform }) {
  return prisma.deviceToken.upsert({
    where: { token },
    update: { userId, platform, lastSeenAt: new Date() },
    create: { userId, token, platform, lastSeenAt: new Date() },
  });
}

async function removeDevice({ token }) {
  await prisma.deviceToken.deleteMany({ where: { token } });
}

function emitNotification(io, userId, notification) {
  io?.to(`user:${userId}`).emit('notification.created', notification);
}

async function notify({ userId, kind, title, body, data, io }) {
  // Respect the user's preferences before persisting or pushing.
  const pref = await prisma.notificationPreference.findUnique({ where: { userId } }).catch(() => null);
  if (pref) {
    if (pref.muteUntil && pref.muteUntil > new Date()) return null;
    const channelPref = (pref.channels || {})[categoryFor(kind)];
    if (channelPref === 'off') return null;
    if (inQuietHours(pref)) {
      // Persist in-app but skip push so we don't buzz the user.
      const notification = await prisma.notification.create({
        data: { userId, kind, title, body, data: data || null },
      });
      emitNotification(io, userId, notification);
      return notification;
    }
  }

  const notification = await prisma.notification.create({
    data: { userId, kind, title, body, data: data || null },
  });
  emitNotification(io, userId, notification);
  const devices = await prisma.deviceToken.findMany({ where: { userId } });
  if (devices.length) {
    await fcm.sendToTokens(
      devices.map((d) => d.token),
      { title, body, data: { kind, notificationId: notification.id, ...(data || {}) } }
    ).catch(() => {});
  }
  return notification;
}

function categoryFor(kind) {
  if (kind === 'CHAT' || kind === 'MENTION') return 'chat';
  if (kind === 'TASK') return 'task';
  if (kind === 'CALL') return 'call';
  if (kind === 'LEAD_FOLLOWUP') return 'lead';
  return 'system';
}

function inQuietHours(pref) {
  if (pref.quietHoursStart == null || pref.quietHoursEnd == null) return false;
  const hour = new Date().getUTCHours(); // approximation — fine for default ops
  const start = pref.quietHoursStart;
  const end = pref.quietHoursEnd;
  if (start === end) return false;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}

async function getPreferences(userId) {
  return prisma.notificationPreference.findUnique({ where: { userId } });
}

async function setPreferences(userId, data) {
  return prisma.notificationPreference.upsert({
    where: { userId },
    update: data,
    create: { userId, ...data },
  });
}

async function groupedListMine({ user, page = 1, pageSize = 30 }) {
  const where = { userId: user.id };
  const items = await prisma.notification.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    skip: (page - 1) * pageSize,
    take: pageSize,
  });
  const groups = {};
  for (const n of items) {
    const cat = categoryFor(n.kind);
    groups[cat] = groups[cat] || [];
    groups[cat].push(n);
  }
  const unread = await prisma.notification.count({ where: { ...where, readAt: null } });
  return { unread, groups };
}

async function listMine({ user, page = 1, pageSize = 30 }) {
  const where = { userId: user.id };
  const [total, items, unread] = await prisma.$transaction([
    prisma.notification.count({ where }),
    prisma.notification.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.notification.count({ where: { ...where, readAt: null } }),
  ]);
  return { total, page, pageSize, unread, items };
}

async function markAllRead(userId) {
  return prisma.notification.updateMany({ where: { userId, readAt: null }, data: { readAt: new Date() } });
}

async function markRead(id, userId) {
  return prisma.notification.updateMany({ where: { id, userId, readAt: null }, data: { readAt: new Date() } });
}

module.exports = {
  registerDevice, removeDevice, notify, listMine, markAllRead, markRead,
  getPreferences, setPreferences, groupedListMine,
};
