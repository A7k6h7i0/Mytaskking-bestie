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

async function startSession({ user, refreshTokenRow, req }) {
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
      ip, userAgent: ua, device, platform,
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

async function listForUser(userId) {
  return prisma.session.findMany({
    where: { userId },
    orderBy: [{ status: 'asc' }, { lastSeenAt: 'desc' }],
  });
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

module.exports = { startSession, touchSession, revoke, revokeAll, listForUser };
