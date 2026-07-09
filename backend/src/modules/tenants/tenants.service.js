'use strict';

const prisma = require('../../database/prisma');
const { hashPassword, sanitize } = require('../auth/auth.service');
const tenant = require('../../services/tenant');
const { Conflict, NotFound, Forbidden, BadRequest } = require('../../utils/errors');

function serializeOrg(row) {
  if (!row) return null;
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    status: row.status,
    branding: row.branding,
    userCount: row._count?.users ?? row.userCount,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

async function list() {
  const rows = await prisma.tenant.findMany({
    orderBy: { createdAt: 'desc' },
    include: { _count: { select: { users: true } } },
  });
  return { items: rows.map(serializeOrg) };
}

async function getById(id) {
  const row = await prisma.tenant.findUnique({
    where: { id },
    include: { _count: { select: { users: true } } },
  });
  if (!row) throw NotFound('Organisation not found');
  return serializeOrg(row);
}

async function createOrg({
  name,
  slug,
  adminName,
  adminUserId,
  adminPassword,
  createdById,
  status = 'ACTIVE',
}) {
  const normalizedSlug = tenant.slugify(slug || name);
  if (!normalizedSlug) throw BadRequest('Organisation slug is required');
  if (normalizedSlug === 'default') {
    throw BadRequest('Reserved organisation slug');
  }

  const storagePrefix = normalizedSlug;
  const existing = await prisma.tenant.findFirst({
    where: { OR: [{ slug: normalizedSlug }, { storagePrefix }] },
  });
  if (existing) throw Conflict('Organisation slug already in use');

  const passwordHash = await hashPassword(adminPassword);
  const result = await prisma.$transaction(async (tx) => {
    const org = await tx.tenant.create({
      data: {
        slug: normalizedSlug,
        name: name.trim(),
        status,
        storagePrefix,
      },
    });

    const admin = await tx.user.create({
      data: {
        userId: adminUserId.trim(),
        passwordHash,
        role: 'ADMIN',
        name: adminName.trim(),
        tenantId: org.id,
        isClient: false,
        status: 'ACTIVE',
        createdById,
      },
    });

    return { org, admin };
  });

  return {
    organisation: serializeOrg({ ...result.org, _count: { users: 1 } }),
    admin: sanitize(result.admin),
  };
}

async function create(input) {
  return createOrg({ ...input, status: 'ACTIVE' });
}

async function register(input) {
  return createOrg({ ...input, status: 'PENDING', createdById: null });
}

async function update(id, input) {
  const existing = await prisma.tenant.findUnique({ where: { id } });
  if (!existing) throw NotFound('Organisation not found');
  if (id === tenant.DEFAULT_TENANT_ID && input.status === 'SUSPENDED') {
    throw Forbidden('Cannot suspend the platform organisation');
  }

  const data = {};
  if (input.name) data.name = input.name.trim();
  if (input.status) data.status = input.status;
  if (input.branding !== undefined) data.branding = input.branding;

  const row = await prisma.tenant.update({
    where: { id },
    data,
    include: { _count: { select: { users: true } } },
  });
  return serializeOrg(row);
}

async function resolvePublic(slug) {
  const row = await tenant.findTenantBySlug(slug);
  if (!row || row.status === 'SUSPENDED' || row.status === 'PENDING') {
    throw NotFound('Organisation not found');
  }
  return { slug: row.slug, name: row.name };
}

module.exports = { list, getById, create, register, update, resolvePublic };
