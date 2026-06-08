'use strict';

const bcrypt = require('bcryptjs');
const prisma = require('../../database/prisma');
const { Unauthorized, Gone, BadRequest } = require('../../utils/errors');
const tokens = require('../../services/tokens');
const sessions = require('../../services/sessions');
const cloudinary = require('../../services/cloudinary');
const r2 = require('../../services/r2');

const SELFIE_ROLES = new Set(['MANAGER', 'PROJECT_COORDINATOR_MANAGER', 'EMPLOYEE', 'TELECALLER']);

async function hashPassword(plain) {
  return bcrypt.hash(plain, 12);
}

async function comparePassword(plain, hash) {
  return bcrypt.compare(plain, hash);
}

function requiresLoginSelfie(user) {
  return !!user && !user.isClient && SELFIE_ROLES.has(user.role);
}

async function storeLoginSelfie({ user, selfieBase64, selfieMimeType }) {
  if (!selfieBase64) throw BadRequest('Take a selfie to sign in');
  const buffer = Buffer.from(selfieBase64, 'base64');
  if (!buffer.length || buffer.length > 3 * 1024 * 1024) {
    throw BadRequest('Selfie must be a valid image smaller than 3 MB');
  }
  if (cloudinary.isConfigured()) {
    const result = await cloudinary.uploadBuffer(buffer, {
      folder: `bestie/login-selfies/${user.id}`,
      publicId: `login-${Date.now()}`,
    });
    return result.secure_url;
  }
  if (r2.isConfigured()) {
    const ext = selfieMimeType === 'image/png' ? 'png' : 'jpg';
    const put = await r2.putBuffer({
      buffer,
      key: `login-selfies/${user.id}/${Date.now()}.${ext}`,
      contentType: selfieMimeType || 'image/jpeg',
    });
    return put.url;
  }
  throw BadRequest('Selfie storage is not configured');
}

async function login({ userId, password, userAgent, ip, req, loginSource, selfieBase64, selfieMimeType }) {
  const user = await prisma.user.findUnique({ where: { userId } });
  if (!user) throw Unauthorized('Invalid credentials');
  if (user.status === 'SUSPENDED') throw Unauthorized('Account suspended');

  if (user.isClient && user.accessEndsAt && user.accessEndsAt < new Date()) {
    await prisma.user.update({ where: { id: user.id }, data: { status: 'EXPIRED' } });
    throw Gone('Client access has expired');
  }

  const ok = await comparePassword(password, user.passwordHash);
  if (!ok) throw Unauthorized('Invalid credentials');
  const selfieUrl = loginSource === 'mobile' && requiresLoginSelfie(user)
    ? await storeLoginSelfie({ user, selfieBase64, selfieMimeType })
    : null;

  const accessToken = tokens.signAccessToken(user);
  const { token: refreshToken, expiresAt, row } = await tokens.issueRefreshToken(user, { userAgent, ip });

  await prisma.user.update({ where: { id: user.id }, data: { lastSeenAt: new Date() } });
  const session = await sessions.startSession({ user, refreshTokenRow: row, req, selfieUrl }).catch(() => null);

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
    .startSession({
      user: rotated.user,
      refreshTokenRow: rotated.row,
      req,
      selfieUrl: rotated.previousSelfieUrl,
    })
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

async function changePassword({ user, currentPassword, newPassword }) {
  const fresh = await prisma.user.findUnique({ where: { id: user.id } });
  if (!fresh) throw Unauthorized('User no longer exists');

  const ok = await comparePassword(currentPassword, fresh.passwordHash);
  if (!ok) throw Unauthorized('Current password is incorrect');

  const passwordHash = await hashPassword(newPassword);
  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash },
  });

  return { ok: true };
}

async function updateProfile({ user, avatarUrl }) {
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { avatarUrl: avatarUrl || null },
  });
  return sanitize(updated);
}

function sanitize(user) {
  // eslint-disable-next-line no-unused-vars
  const { passwordHash, ...safe } = user;
  return safe;
}

module.exports = {
  login,
  refresh,
  logout,
  changePassword,
  updateProfile,
  requiresLoginSelfie,
  hashPassword,
  sanitize,
};
