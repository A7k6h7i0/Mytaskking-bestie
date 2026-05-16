'use strict';

const bcrypt = require('bcryptjs');
const prisma = require('../../database/prisma');
const { Unauthorized, Gone } = require('../../utils/errors');
const tokens = require('../../services/tokens');
const sessions = require('../../services/sessions');

async function hashPassword(plain) {
  return bcrypt.hash(plain, 12);
}

async function comparePassword(plain, hash) {
  return bcrypt.compare(plain, hash);
}

async function login({ userId, password, userAgent, ip, req }) {
  const user = await prisma.user.findUnique({ where: { userId } });
  if (!user) throw Unauthorized('Invalid credentials');
  if (user.status === 'SUSPENDED') throw Unauthorized('Account suspended');

  if (user.isClient && user.accessEndsAt && user.accessEndsAt < new Date()) {
    await prisma.user.update({ where: { id: user.id }, data: { status: 'EXPIRED' } });
    throw Gone('Client access has expired');
  }

  const ok = await comparePassword(password, user.passwordHash);
  if (!ok) throw Unauthorized('Invalid credentials');

  const accessToken = tokens.signAccessToken(user);
  const { token: refreshToken, expiresAt, row } = await tokens.issueRefreshToken(user, { userAgent, ip });

  await prisma.user.update({ where: { id: user.id }, data: { lastSeenAt: new Date() } });
  const session = await sessions.startSession({ user, refreshTokenRow: row, req }).catch(() => null);

  return {
    user: sanitize(user),
    accessToken,
    refreshToken,
    refreshExpiresAt: expiresAt,
    session: session ? { id: session.id, riskScore: session.riskScore } : null,
  };
}

async function refresh({ refreshToken, userAgent, ip, req }) {
  const rotated = await tokens.rotateRefreshToken(refreshToken, { userAgent, ip });
  if (!rotated) throw Unauthorized('Invalid refresh token');

  const accessToken = tokens.signAccessToken(rotated.user);

  // Refresh rotation = new RefreshToken row. We also start a fresh Session row
  // (the old one stays around as a history record). The refresh token has the
  // session linked via `refreshTokenId`.
  const session = await sessions
    .startSession({ user: rotated.user, refreshTokenRow: rotated.row, req })
    .catch(() => null);

  return {
    user: sanitize(rotated.user),
    accessToken,
    refreshToken: rotated.token,
    refreshExpiresAt: rotated.expiresAt,
    session: session ? { id: session.id, riskScore: session.riskScore } : null,
  };
}

async function logout({ refreshToken }) {
  if (refreshToken) await tokens.revokeRefreshToken(refreshToken);
}

function sanitize(user) {
  // eslint-disable-next-line no-unused-vars
  const { passwordHash, ...safe } = user;
  return safe;
}

module.exports = { login, refresh, logout, hashPassword, sanitize };
