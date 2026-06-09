'use strict';

const prisma = require('../database/prisma');

/**
 * Session bookkeeping — every successful login creates a Session row linked
 * to the RefreshToken row. Logout / refresh-rotate / force-logout flip its
 * status. Enables device list, login history, and "sign out everywhere".
 */

const RISK_THRESHOLDS = {
  newCountry: 30,
  newDevice: 20,
  impossibleTravel: 50,
};

async function startSession({
  user,
  refreshTokenRow,
  req,
  selfieUrl = null,
  latitude = null,
  longitude = null,
  address = null,
}) {
  const ip = req?.ip || null;
  const ua = req?.headers?.['user-agent'] || null;
  const { device, platform } = parseUA(ua);

  // Compute a tiny risk score from recent sessions for this user.
  const recent = await prisma.session.findMany({
    where: { userId: user.id, status: 'ACTIVE' },
    orderBy: { lastSeenAt: 'desc' },
    take: 10,
  });
  let risk = 0;
  if (recent.length > 0) {
    const knownIps = new Set(recent.map((s) => s.ip).filter(Boolean));
    if (ip && !knownIps.has(ip)) risk += RISK_THRESHOLDS.newDevice;
    const knownDevices = new Set(recent.map((s) => s.device).filter(Boolean));
    if (device && !knownDevices.has(device)) risk += RISK_THRESHOLDS.newDevice;
  }

  return prisma.session.create({
    data: {
      userId: user.id,
      refreshTokenId: refreshTokenRow?.id || null,
      ip, userAgent: ua, device, platform, selfieUrl,
      latitude, longitude, address: address || null,
      riskScore: Math.min(risk, 100),
    },
  });
}

async function touchSession(sessionId) {
  if (!sessionId) return;
  await prisma.session.update({ where: { id: sessionId }, data: { lastSeenAt: new Date() } }).catch(() => {});
}

async function revoke({ id, actor, force }) {
  const session = await prisma.session.findUnique({ where: { id } });
  if (!session) return null;
  if (session.userId !== actor.id && !['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
    const err = new Error('Forbidden'); err.status = 403; throw err;
  }
  const [s] = await prisma.$transaction([
    prisma.session.update({
      where: { id },
      data: { status: force ? 'FORCED_OUT' : 'REVOKED', revokedAt: new Date() },
    }),
    session.refreshTokenId
      ? prisma.refreshToken.update({ where: { id: session.refreshTokenId }, data: { revokedAt: new Date() } })
      : Promise.resolve(null),
  ]);
  return s;
}

async function revokeAll({ userId, exceptSessionId, actor, force }) {
  if (userId !== actor.id && !['SUPER_ADMIN', 'ADMIN'].includes(actor.role)) {
    const err = new Error('Forbidden'); err.status = 403; throw err;
  }
  const sessions = await prisma.session.findMany({
    where: {
      userId,
      status: 'ACTIVE',
      ...(exceptSessionId ? { NOT: { id: exceptSessionId } } : {}),
    },
  });
  await prisma.$transaction([
    prisma.session.updateMany({
      where: { id: { in: sessions.map((s) => s.id) } },
      data: { status: force ? 'FORCED_OUT' : 'REVOKED', revokedAt: new Date() },
    }),
    prisma.refreshToken.updateMany({
      where: { id: { in: sessions.map((s) => s.refreshTokenId).filter(Boolean) } },
      data: { revokedAt: new Date() },
    }),
  ]);
  return { revoked: sessions.length };
}

async function listForUser(userId, { includeSelfie = false } = {}) {
  const rows = await prisma.session.findMany({
    where: { userId },
    orderBy: [{ status: 'asc' }, { lastSeenAt: 'desc' }],
  });
  if (includeSelfie) return rows;
  return rows.map(({ selfieUrl: _selfieUrl, ...row }) => row);
}

/**
 * Org-wide login/logout activity for admins (#2). Returns sessions across all
 * users with login (firstSeenAt) + logout (revokedAt) timestamps, device, ip,
 * and whether the session is still active. Filterable by user and date range.
 */
async function listActivity({ userId, from, to, page = 1, pageSize = 50, includeSelfie = false } = {}) {
  const where = {};
  if (userId) where.userId = userId;
  if (from || to) {
    where.firstSeenAt = {};
    if (from) where.firstSeenAt.gte = from;
    if (to) where.firstSeenAt.lte = to;
  }
  const [total, rows] = await Promise.all([
    prisma.session.count({ where }),
    prisma.session.findMany({
      where,
      orderBy: { firstSeenAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
  ]);
  // Session has no relation to User in the schema, so resolve names separately.
  const userIds = Array.from(new Set(rows.map((r) => r.userId)));
  const users = await prisma.user.findMany({
    where: { id: { in: userIds } },
    select: { id: true, name: true, role: true, avatarUrl: true, isClient: true, customTitle: true },
  });
  const byId = new Map(users.map((u) => [u.id, u]));
  const items = rows.map((r) => ({
    id: r.id,
    user: byId.get(r.userId) || { id: r.userId, name: 'Unknown' },
    status: r.status,
    loginAt: r.firstSeenAt,
    lastSeenAt: r.lastSeenAt,
    logoutAt: r.revokedAt,
    device: r.device,
    platform: r.platform,
    ip: r.ip,
    city: r.city,
    country: r.country,
    ...(includeSelfie ? {
      selfieUrl: r.selfieUrl,
      latitude: r.latitude,
      longitude: r.longitude,
      address: r.address,
    } : {}),
  }));
  return { total, page, pageSize, items };
}

function parseUA(ua) {
  if (!ua) return { device: null, platform: null };
  const lower = ua.toLowerCase();
  let platform = 'web';
  if (lower.includes('android')) platform = 'android';
  else if (lower.includes('iphone') || lower.includes('ipad')) platform = 'ios';
  else if (lower.includes('windows')) platform = 'windows';
  else if (lower.includes('mac os')) platform = 'macos';
  else if (lower.includes('linux')) platform = 'linux';
  const m = ua.match(/\(([^)]+)\)/);
  const device = m ? m[1].split(';')[0].trim() : null;
  return { device, platform };
}

module.exports = { startSession, touchSession, revoke, revokeAll, listForUser, listActivity };
