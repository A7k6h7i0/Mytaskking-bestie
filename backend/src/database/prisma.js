'use strict';

const { PrismaClient } = require('@prisma/client');
const logger = require('../utils/logger');

const prisma = new PrismaClient({
  log: [
    { emit: 'event', level: 'error' },
    { emit: 'event', level: 'warn' },
  ],
});

prisma.$on('error', (e) => logger.error({ msg: e.message }, 'prisma.error'));
prisma.$on('warn', (e) => logger.warn({ msg: e.message }, 'prisma.warn'));

module.exports = prisma;
