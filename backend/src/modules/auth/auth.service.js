'use strict';

const bcrypt = require('bcryptjs');
const prisma = require('../../database/prisma');
const { Unauthorized, Gone, BadRequest } = require('../../utils/errors');
const tokens = require('../../services/tokens');
const sessions = require('../../services/sessions');
const cloudinary = require('../../services/cloudinary');
const r2 = require('../../services/r2');
const logger = require('../../utils/logger');
const tenantService = require('../../services/tenant');

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
  const uploadToR2 = async () => {
    const ext = selfieMimeType === 'image/png' ? 'png' : 'jpg';
    const put = await r2.putBuffer({
      buffer,
      key: `login-selfies/${user.id}/${Date.now()}.${ext}`,
      contentType: selfieMimeType || 'image/jpeg',
    });
    return put.url;
  };

  if (cloudinary.isConfigured()) {
    try {
      const result = await cloudinary.uploadBuffer(buffer, {
        folder: `bestie/login-selfies/${user.id}`,
        publicId: `login-${Date.now()}`,
      });
      return result.secure_url;
    } catch (err) {
      logger.warn({ err: err.message, userId: user.id }, 'auth.login_selfie.cloudinary_failed_falling_back_to_r2');
      if (!r2.isConfigured()) throw err;
      return uploadToR2();
    }
  }
  if (r2.isConfigured()) {
    return uploadToR2();
  }
  throw BadRequest('Selfie storage is not configured');
}

async function login({
  tenantSlug,
  userId,
  password,
  userAgent,
  ip,
  req,
  loginSource,
  selfieBase64,
  selfieMimeType,
  latitude,
  longitude,
  address,
}) {
  const { tenant, user, pendingApproval } = await tenantService.findUserForLogin({
    tenantSlug,
    userId,
  });
  if (!tenant) throw Unauthorized('Organisation not found');
  if (pendingApproval) {
    throw Unauthorized(
      'Organisation registration is pending approval. You can sign in after a platform administrator approves your organisation.',
    );
  }
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

  await prisma.user
    .update({ where: { id: user.id }, data: { lastSeenAt: new Date() } })
    .catch(() => prisma.$executeRaw`
      UPDATE "User" SET "lastSeenAt" = NOW() WHERE id = ${user.id}
    `.catch(() => {}));
  const session = await sessions.startSession({
    user,
    refreshTokenRow: row,
    req,
    selfieUrl,
    latitude,
    longitude,
    address,
    replaceSameDevice: true,
  }).catch(() => null);

  return {
    user: await sanitizeWithTenant(user),
    tenant: { id: tenant.id, slug: tenant.slug, name: tenant.name },
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
      latitude: rotated.previousLocation?.latitude,
      longitude: rotated.previousLocation?.longitude,
      address: rotated.previousLocation?.address,
    })
    .catch(() => null);

  return {
    user: await sanitizeWithTenant(rotated.user),
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

async function updateProfile({ user, avatarUrl, phone }) {
  const data = {};
  if (avatarUrl !== undefined) data.avatarUrl = avatarUrl || null;
  if (phone !== undefined) data.phone = phone || null;
  const updated = await prisma.user.update({
    where: { id: user.id },
    data,
  });
  return sanitizeWithTenant(updated);
}

function sanitize(user) {
  // eslint-disable-next-line no-unused-vars
  const { passwordHash, ...safe } = user;
  return safe;
}

async function sanitizeWithTenant(user) {
  const safe = sanitize(user);
  const tenantId = user.tenantId || tenantService.DEFAULT_TENANT_ID;
  try {
    const t = await prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, slug: true, name: true },
    });
    if (t) return { ...safe, tenant: t };
  } catch (_) {
    /* pre-migration DB */
  }
  return {
    ...safe,
    tenant: {
      id: tenantId,
      slug: 'default',
      name: process.env.WORKSPACE_NAME || 'MyTaskKing',
    },
  };
}

async function loginRequirements({ tenantSlug, userId }) {
  const { user } = await tenantService.findUserForLogin({ tenantSlug, userId });
  return { requiresSelfie: requiresLoginSelfie(user) };
}

module.exports = {
  login,
  refresh,
  logout,
  changePassword,
  updateProfile,
  requiresLoginSelfie,
  loginRequirements,
  hashPassword,
  sanitize,
  sanitizeWithTenant,
};
