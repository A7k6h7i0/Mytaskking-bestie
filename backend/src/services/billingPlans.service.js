'use strict';

const prisma = require('../database/prisma');
const { BadRequest, NotFound } = require('../utils/errors');

function serializePlan(row) {
  return {
    id: row.id,
    planMonths: row.months,
    months: row.months,
    label: row.label,
    amountPaise: row.amountPaise,
    amountInr: row.amountPaise / 100,
    currency: row.currency,
    isActive: row.isActive,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

const DEFAULT_PLANS = [
  {
    id: 'plan_1m_default',
    months: 1,
    label: '1 month',
    amountPaise: Number(process.env.PLAN_1_MONTH_PAISE || 99900),
    sortOrder: 1,
  },
  {
    id: 'plan_6m_default',
    months: 6,
    label: '6 months',
    amountPaise: Number(process.env.PLAN_6_MONTH_PAISE || 499900),
    sortOrder: 2,
  },
  {
    id: 'plan_12m_default',
    months: 12,
    label: '12 months',
    amountPaise: Number(process.env.PLAN_12_MONTH_PAISE || 899900),
    sortOrder: 3,
  },
];

async function seedDefaultPlansIfEmpty() {
  const count = await prisma.billingPlan.count();
  if (count > 0) return;
  for (const plan of DEFAULT_PLANS) {
    await prisma.billingPlan.create({
      data: {
        id: plan.id,
        months: plan.months,
        label: plan.label,
        amountPaise: plan.amountPaise,
        currency: 'INR',
        isActive: true,
        sortOrder: plan.sortOrder,
      },
    });
  }
}

async function listPlans({ activeOnly = false } = {}) {
  await seedDefaultPlansIfEmpty();
  const rows = await prisma.billingPlan.findMany({
    where: activeOnly ? { isActive: true } : {},
    orderBy: [{ sortOrder: 'asc' }, { months: 'asc' }],
  });
  return rows.map(serializePlan);
}

async function getPlanById(id, { activeOnly = false } = {}) {
  await seedDefaultPlansIfEmpty();
  const row = await prisma.billingPlan.findUnique({ where: { id } });
  if (!row) throw NotFound('Plan not found');
  if (activeOnly && !row.isActive) throw BadRequest('Plan is not available');
  return row;
}

async function resolvePlan({ planId, planMonths }) {
  await seedDefaultPlansIfEmpty();
  if (planId) return getPlanById(planId, { activeOnly: true });
  if (planMonths != null) {
    const row = await prisma.billingPlan.findFirst({
      where: { months: Number(planMonths), isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });
    if (row) return row;
  }
  throw BadRequest('Invalid subscription plan');
}

async function createPlan(input) {
  if (!input.label?.trim()) throw BadRequest('Label is required');
  if (!Number.isInteger(input.months) || input.months < 1) {
    throw BadRequest('Duration must be at least 1 month');
  }
  if (!Number.isInteger(input.amountPaise) || input.amountPaise < 100) {
    throw BadRequest('Amount must be at least ₹1');
  }
  const row = await prisma.billingPlan.create({
    data: {
      months: input.months,
      label: input.label.trim(),
      amountPaise: input.amountPaise,
      currency: input.currency || 'INR',
      isActive: input.isActive !== false,
      sortOrder: Number.isInteger(input.sortOrder) ? input.sortOrder : 0,
    },
  });
  return serializePlan(row);
}

async function updatePlan(id, input) {
  const existing = await getPlanById(id);
  const data = {};
  if (input.label !== undefined) data.label = input.label.trim();
  if (input.months !== undefined) {
    if (!Number.isInteger(input.months) || input.months < 1) {
      throw BadRequest('Duration must be at least 1 month');
    }
    data.months = input.months;
  }
  if (input.amountPaise !== undefined) {
    if (!Number.isInteger(input.amountPaise) || input.amountPaise < 100) {
      throw BadRequest('Amount must be at least ₹1');
    }
    data.amountPaise = input.amountPaise;
  }
  if (input.currency !== undefined) data.currency = input.currency;
  if (input.isActive !== undefined) data.isActive = input.isActive;
  if (input.sortOrder !== undefined) data.sortOrder = input.sortOrder;
  const row = await prisma.billingPlan.update({ where: { id: existing.id }, data });
  return serializePlan(row);
}

async function deletePlan(id) {
  const existing = await getPlanById(id);
  const inUse = await prisma.tenantSubscription.count({ where: { planId: id } });
  if (inUse > 0) {
    const row = await prisma.billingPlan.update({
      where: { id: existing.id },
      data: { isActive: false },
    });
    return { deleted: false, deactivated: true, plan: serializePlan(row) };
  }
  await prisma.billingPlan.delete({ where: { id: existing.id } });
  return { deleted: true, deactivated: false };
}

module.exports = {
  serializePlan,
  seedDefaultPlansIfEmpty,
  listPlans,
  getPlanById,
  resolvePlan,
  createPlan,
  updatePlan,
  deletePlan,
};
