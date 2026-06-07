'use strict';

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const config = require('../config');
const prisma = require('../database/prisma');

function signAccessToken(user) {
  return jwt.sign(
    {
      sub: user.id,
      uid: user.userId,
      role: user.role,
      isClient: user.isClient,
    },
    config.jwt.accessSecret,
    { expiresIn: config.jwt.accessTtl, issuer: 'bestie' }
  );
}

function verifyAccessToken(token) {
  return jwt.verify(token, config.jwt.accessSecret, { issuer: 'bestie' });
}

async function issueRefreshToken(user, { userAgent, ip } = {}) {
  const raw = crypto.randomBytes(64).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(raw).digest('hex');
  const ttlMs = parseTtl(config.jwt.refreshTtl);
  const expiresAt = new Date(Date.now() + ttlMs);

  const row = await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash,
      userAgent: userAgent || null,
      ip: ip || null,
      expiresAt,
    },
  });

  return { token: raw, expiresAt, row };
}

async function rotateRefreshToken(rawToken, { userAgent, ip } = {}) {
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const existing = await prisma.refreshToken.findUnique({
    where: { tokenHash },
    include: { user: true },
  });

  if (!existing || existing.revokedAt || existing.expiresAt < new Date()) {
    return null;
  }

  await prisma.refreshToken.update({
    where: { id: existing.id },
    data: { revokedAt: new Date() },
  });

  return issueRefreshToken(existing.user, { userAgent, ip }).then((issued) => ({
    user: existing.user,
    ...issued,
  }));
}

async function revokeRefreshToken(rawToken) {
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const now = new Date();
  // Find the row first so we can also close the linked session (login-activity
  // log) — otherwise a logged-out session shows "Active" forever.
  const row = await prisma.refreshToken.findUnique({ where: { tokenHash } });
  await prisma.refreshToken.updateMany({
    where: { tokenHash, revokedAt: null },
    data: { revokedAt: now },
  });
  if (row) {
    await prisma.session
      .updateMany({
        where: { refreshTokenId: row.id, revokedAt: null },
        data: { revokedAt: now, status: 'REVOKED' },
      })
      .catch(() => {});
  }
}

function parseTtl(ttl) {
  const match = /^(\d+)(ms|s|m|h|d)$/.exec(ttl);
  if (!match) return 0;
  const n = parseInt(match[1], 10);
  switch (match[2]) {
    case 'ms': return n;
    case 's': return n * 1000;
    case 'm': return n * 60_000;
    case 'h': return n * 3_600_000;
    case 'd': return n * 86_400_000;
    default: return 0;
  }
}

module.exports = {
  signAccessToken,
  verifyAccessToken,
  issueRefreshToken,
  rotateRefreshToken,
  revokeRefreshToken,
};
