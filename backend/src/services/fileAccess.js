'use strict';

const prisma = require('../database/prisma');

/**
 * Resolves whether `user` can access `file`, given an optional explicit channel
 * context. Centralizing here keeps the four read paths (download URL, preview,
 * version history, register) in lockstep.
 */
async function canAccess({ file, user, channelId }) {
  if (!file) return false;
  if (file.uploadedById === user.id) return true;
  if (['SUPER_ADMIN', 'ADMIN'].includes(user.role)) return true;

  const policy = await prisma.fileAccessPolicy.findUnique({ where: { fileId: file.id } }).catch(() => null);
  if (policy?.expiresAt && policy.expiresAt < new Date()) return false;

  const visibility = policy?.visibility || 'PRIVATE';

  if (visibility === 'PUBLIC') return true;
  if (visibility === 'TENANT') return file.tenantId == null || file.tenantId === user.tenantId;

  if (visibility === 'CHANNEL') {
    const cid = policy?.channelId || channelId;
    if (!cid) return false;
    const member = await prisma.channelMember.findUnique({
      where: { channelId_userId: { channelId: cid, userId: user.id } },
    });
    return !!member;
  }

  // PRIVATE — fall back to explicit grants
  const grant = await prisma.fileGrant.findUnique({
    where: { fileId_userId: { fileId: file.id, userId: user.id } },
  });
  if (!grant) return false;
  if (grant.expiresAt && grant.expiresAt < new Date()) return false;
  return true;
}

async function setPolicy({ fileId, data }) {
  return prisma.fileAccessPolicy.upsert({
    where: { fileId },
    update: data,
    create: { fileId, ...data },
  });
}

async function grant({ fileId, userId, canDownload = true, expiresAt = null }) {
  return prisma.fileGrant.upsert({
    where: { fileId_userId: { fileId, userId } },
    update: { canDownload, expiresAt },
    create: { fileId, userId, canDownload, expiresAt },
  });
}

async function revoke({ fileId, userId }) {
  await prisma.fileGrant
    .delete({ where: { fileId_userId: { fileId, userId } } })
    .catch(() => {});
}

module.exports = { canAccess, setPolicy, grant, revoke };
