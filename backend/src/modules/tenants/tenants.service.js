'use strict';

const prisma = require('../../database/prisma');
const { hashPassword, sanitize } = require('../auth/auth.service');
const tenant = require('../../services/tenant');
const email = require('../../services/email');
const { Conflict, NotFound, Forbidden, BadRequest } = require('../../utils/errors');

const GOVT_ID_TYPES = new Set(['AADHAAR', 'PAN', 'VOTER_ID', 'DRIVING_LICENSE']);

function validateGovtId(type, number) {
  const n = String(number || '').trim();
  if (!GOVT_ID_TYPES.has(type)) throw BadRequest('Invalid government ID type');
  if (type === 'AADHAAR' && !/^\d{12}$/.test(n.replace(/\s/g, ''))) {
    throw BadRequest('Aadhaar must be 12 digits');
  }
  if (type === 'PAN' && !/^[A-Z]{5}\d{4}[A-Z]$/i.test(n)) {
    throw BadRequest('PAN format invalid');
  }
  if (n.length < 4) throw BadRequest('Government ID number is too short');
  return n.toUpperCase();
}

function serializeOrg(row) {
  if (!row) return null;
  const registration = row.registration
    ? {
        adminPhone: row.registration.adminPhone,
        adminEmail: row.registration.adminEmail,
        emailVerifiedAt: row.registration.emailVerifiedAt,
        govtId1Type: row.registration.govtId1Type,
        govtId1Number: row.registration.govtId1Number,
        govtId1ImageUrl: row.registration.govtId1ImageUrl,
        govtId2Type: row.registration.govtId2Type,
        govtId2Number: row.registration.govtId2Number,
        govtId2ImageUrl: row.registration.govtId2ImageUrl,
        reviewStatus: row.registration.reviewStatus,
        reviewedAt: row.registration.reviewedAt,
        rejectReason: row.registration.rejectReason,
        submittedAt: row.registration.submittedAt,
      }
    : null;
  const subscription = row.subscription
    ? {
        status: row.subscription.status,
        planId: row.subscription.planId,
        planMonths: row.subscription.planMonths,
        planLabel: row.subscription.billingPlan?.label ?? null,
        trialEndsAt: row.subscription.trialEndsAt,
        paidUntil: row.subscription.paidUntil,
        amountPaise: row.subscription.amountPaise,
        currency: row.subscription.currency,
        paidAt: row.subscription.paidAt,
        paymentReference: row.subscription.paymentReference,
        razorpayOrderId: row.subscription.razorpayOrderId,
        razorpayPaymentId: row.subscription.razorpayPaymentId,
      }
    : null;
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    status: row.status,
    branding: row.branding,
    userCount: row._count?.users ?? row.userCount,
    registration,
    subscription,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

const orgInclude = {
  _count: { select: { users: true } },
  registration: true,
  subscription: { include: { billingPlan: true } },
};

async function list({ reviewStatus } = {}) {
  const where = {};
  if (reviewStatus) {
    where.registration = { reviewStatus };
  }
  const rows = await prisma.tenant.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    include: orgInclude,
  });
  return { items: rows.map(serializeOrg) };
}

async function listRegistrations() {
  const rows = await prisma.tenant.findMany({
    where: {
      registration: {
        reviewStatus: { in: ['SUBMITTED', 'UNDER_REVIEW', 'REJECTED'] },
      },
    },
    orderBy: { createdAt: 'desc' },
    include: orgInclude,
  });
  return { items: rows.map(serializeOrg) };
}

async function getById(id) {
  const row = await prisma.tenant.findUnique({
    where: { id },
    include: orgInclude,
  });
  if (!row) throw NotFound('Organisation not found');
  return serializeOrg(row);
}

async function removeRejectedTenantIfAny(normalizedSlug) {
  const existing = await prisma.tenant.findUnique({
    where: { slug: normalizedSlug },
    include: { registration: true },
  });
  if (!existing) return;
  const rejected =
    existing.registration?.reviewStatus === 'REJECTED' || existing.status === 'SUSPENDED';
  if (!rejected) throw Conflict('Organisation slug already in use');
  await prisma.tenant.delete({ where: { id: existing.id } });
}

async function createOrg({
  name,
  slug,
  adminName,
  adminUserId,
  adminPassword,
  adminEmail,
  adminPhone,
  createdById,
  status = 'ACTIVE',
  registrationExtra,
  subscriptionExtra,
}) {
  const normalizedSlug = tenant.slugify(slug || name);
  if (!normalizedSlug) throw BadRequest('Organisation slug is required');
  if (normalizedSlug === 'default') throw BadRequest('Reserved organisation slug');

  await removeRejectedTenantIfAny(normalizedSlug);

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
        email: adminEmail?.trim() || null,
        phone: adminPhone?.trim() || null,
        tenantId: org.id,
        isClient: false,
        status: 'ACTIVE',
        createdById,
      },
    });

    if (registrationExtra) {
      await tx.tenantRegistration.create({
        data: { tenantId: org.id, ...registrationExtra },
      });
    }

    if (subscriptionExtra) {
      await tx.tenantSubscription.create({
        data: { tenantId: org.id, ...subscriptionExtra },
      });
    }

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
  const adminEmail = String(input.adminEmail || '').trim().toLowerCase();
  const adminPhone = String(input.adminPhone || '').replace(/\D/g, '');
  if (!adminEmail.includes('@')) throw BadRequest('Valid admin email is required');
  if (adminPhone.length < 10) throw BadRequest('Valid phone number is required');

  const govtId1Type = String(input.govtId1Type || '').toUpperCase();
  const govtId2Type = String(input.govtId2Type || '').toUpperCase();
  if (govtId1Type === govtId2Type) {
    throw BadRequest('Select two different government ID types');
  }

  const registrationExtra = {
    adminPhone,
    adminEmail,
    emailVerifiedAt: null,
    govtId1Type,
    govtId1Number: validateGovtId(govtId1Type, input.govtId1Number),
    govtId1ImageUrl: input.govtId1ImageUrl || null,
    govtId2Type,
    govtId2Number: validateGovtId(govtId2Type, input.govtId2Number),
    govtId2ImageUrl: input.govtId2ImageUrl || null,
    reviewStatus: 'SUBMITTED',
  };

  const result = await createOrg({
    name: input.name,
    slug: input.slug,
    adminName: input.adminName,
    adminUserId: input.adminUserId,
    adminPassword: input.adminPassword,
    adminEmail,
    adminPhone,
    createdById: null,
    status: 'PENDING',
    registrationExtra,
    subscriptionExtra: { status: 'NONE' },
  });

  try {
    const salesHead = await prisma.user.findFirst({
      where: { role: 'SALES_HEAD', tenantId: tenant.DEFAULT_TENANT_ID, status: 'ACTIVE' },
    });
    if (salesHead?.email) {
      await email.send({
        to: salesHead.email,
        subject: `New organisation registration: ${result.organisation.name}`,
        text: `A new organisation "${result.organisation.name}" (${result.organisation.slug}) submitted registration and awaits review.`,
        html: `<p>A new organisation <strong>${result.organisation.name}</strong> (<code>${result.organisation.slug}</code>) submitted registration.</p>`,
        tags: ['tenant.registration'],
      });
    }
  } catch (_) {}

  return result;
}

async function approveRegistration(id, reviewerId) {
  const row = await prisma.tenant.findUnique({
    where: { id },
    include: { registration: true, subscription: true },
  });
  if (!row) throw NotFound('Organisation not found');
  if (!row.registration) throw BadRequest('No registration record for this organisation');

  await prisma.$transaction(async (tx) => {
    await tx.tenant.update({ where: { id }, data: { status: 'ACTIVE' } });
    await tx.tenantRegistration.update({
      where: { tenantId: id },
      data: {
        reviewStatus: 'APPROVED',
        reviewedById: reviewerId,
        reviewedAt: new Date(),
        rejectReason: null,
      },
    });
    const sub = row.subscription;
    if (sub?.status === 'TRIAL_REQUESTED') {
      const trialEndsAt = new Date();
      trialEndsAt.setDate(trialEndsAt.getDate() + 7);
      await tx.tenantSubscription.update({
        where: { tenantId: id },
        data: { status: 'TRIAL_ACTIVE', trialEndsAt },
      });
    }
  });

  return getById(id);
}

async function rejectRegistration(id, reviewerId, reason) {
  const row = await prisma.tenant.findUnique({
    where: { id },
    include: { registration: true },
  });
  if (!row) throw NotFound('Organisation not found');
  if (!row.registration) throw BadRequest('No registration record');

  await prisma.$transaction(async (tx) => {
    await tx.tenant.update({ where: { id }, data: { status: 'SUSPENDED' } });
    await tx.tenantRegistration.update({
      where: { tenantId: id },
      data: {
        reviewStatus: 'REJECTED',
        reviewedById: reviewerId,
        reviewedAt: new Date(),
        rejectReason: reason || 'Rejected by sales head',
      },
    });
  });

  return getById(id);
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
    include: orgInclude,
  });
  return serializeOrg(row);
}

async function updateSubscription(id, input) {
  const existing = await prisma.tenant.findUnique({ where: { id } });
  if (!existing) throw NotFound('Organisation not found');
  const data = {};
  if (input.status) data.status = input.status;
  if (input.planMonths !== undefined) data.planMonths = input.planMonths;
  if (input.trialEndsAt !== undefined) {
    data.trialEndsAt = input.trialEndsAt ? new Date(input.trialEndsAt) : null;
  }
  if (input.paidUntil !== undefined) {
    data.paidUntil = input.paidUntil ? new Date(input.paidUntil) : null;
  }
  const row = await prisma.tenantSubscription.upsert({
    where: { tenantId: id },
    create: { tenantId: id, ...data },
    update: data,
    include: { tenant: { include: orgInclude } },
  });
  return serializeOrg(row.tenant);
}

async function remove(id) {
  if (id === tenant.DEFAULT_TENANT_ID) {
    throw Forbidden('Cannot delete the platform organisation');
  }
  const existing = await prisma.tenant.findUnique({ where: { id } });
  if (!existing) throw NotFound('Organisation not found');
  await prisma.tenant.delete({ where: { id } });
  return { ok: true };
}

async function resolvePublic(slug) {
  const row = await tenant.findTenantBySlug(slug);
  if (!row || row.status === 'SUSPENDED' || row.status === 'PENDING') {
    throw NotFound('Organisation not found');
  }
  return { slug: row.slug, name: row.name };
}

module.exports = {
  list,
  listRegistrations,
  getById,
  create,
  register,
  update,
  updateSubscription,
  approveRegistration,
  rejectRegistration,
  remove,
  resolvePublic,
};
