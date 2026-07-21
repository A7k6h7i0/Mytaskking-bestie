'use strict';

const bcrypt = require('bcryptjs');
const prisma = require('./prisma');
const config = require('../config');
const logger = require('../utils/logger');

const ATTENDANCE_MIN_WORDS =
  Number(process.env.ATTENDANCE_MIN_REQUIRED_WORDS) || 10;

async function seedAttendanceConfig() {
  await prisma.workspaceSetting.upsert({
    where: { scope_key: { scope: 'attendance', key: 'minRequiredWords' } },
    create: {
      scope: 'attendance',
      key: 'minRequiredWords',
      value: ATTENDANCE_MIN_WORDS,
    },
    update: { value: ATTENDANCE_MIN_WORDS },
  });
  logger.info({ minRequiredWords: ATTENDANCE_MIN_WORDS }, 'seed.attendance_config');
}

async function main() {
  const tenantService = require('../services/tenant');
  await tenantService.ensureDefaultTenant();
  await seedAttendanceConfig();

  const userId = config.seed.superAdminUserId;
  const existing = await prisma.user.findUnique({
    where: {
      tenantId_userId: { tenantId: tenantService.DEFAULT_TENANT_ID, userId },
    },
  });
  if (existing) {
    logger.info({ userId }, 'seed.super_admin.exists');
  } else {
    const passwordHash = await bcrypt.hash(config.seed.superAdminPassword, 12);
    const user = await prisma.user.create({
      data: {
        userId,
        passwordHash,
        role: 'SUPER_ADMIN',
        name: config.seed.superAdminName,
        isClient: false,
        status: 'ACTIVE',
        tenantId: tenantService.DEFAULT_TENANT_ID,
      },
    });
    logger.info({ id: user.id, userId: user.userId }, 'seed.super_admin.created');
  }

  const salesHeadUserId = process.env.SALES_HEAD_USER_ID || 'saleshead';
  const salesHeadExisting = await prisma.user.findUnique({
    where: {
      tenantId_userId: { tenantId: tenantService.DEFAULT_TENANT_ID, userId: salesHeadUserId },
    },
  });
  if (salesHeadExisting) {
    logger.info({ userId: salesHeadUserId }, 'seed.sales_head.exists');
  } else {
    const salesHeadPassword = process.env.SALES_HEAD_PASSWORD || 'SalesHead@123';
    const salesHeadHash = await bcrypt.hash(salesHeadPassword, 12);
    const salesHead = await prisma.user.create({
      data: {
        userId: salesHeadUserId,
        passwordHash: salesHeadHash,
        role: 'SALES_HEAD',
        name: process.env.SALES_HEAD_NAME || 'Sales Head',
        email: process.env.SALES_HEAD_EMAIL || null,
        isClient: false,
        status: 'ACTIVE',
        tenantId: tenantService.DEFAULT_TENANT_ID,
      },
    });
    logger.info({ id: salesHead.id, userId: salesHead.userId }, 'seed.sales_head.created');
  }

  const billingPlans = require('../services/billingPlans.service');
  await billingPlans.seedDefaultPlansIfEmpty();
  logger.info('seed.billing_plans.ready');
}

main()
  .catch((err) => {
    logger.error({ err }, 'seed.failed');
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
