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
  await seedAttendanceConfig();

  const userId = config.seed.superAdminUserId;
  const existing = await prisma.user.findUnique({ where: { userId } });
  if (existing) {
    logger.info({ userId }, 'seed.super_admin.exists');
    return;
  }
  const passwordHash = await bcrypt.hash(config.seed.superAdminPassword, 12);
  const user = await prisma.user.create({
    data: {
      userId,
      passwordHash,
      role: 'SUPER_ADMIN',
      name: config.seed.superAdminName,
      isClient: false,
      status: 'ACTIVE',
    },
  });
  logger.info({ id: user.id, userId: user.userId }, 'seed.super_admin.created');
}

main()
  .catch((err) => {
    logger.error({ err }, 'seed.failed');
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
