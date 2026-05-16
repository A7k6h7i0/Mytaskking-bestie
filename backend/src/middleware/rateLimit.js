'use strict';

const rateLimit = require('express-rate-limit');

const baseLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 240,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: { code: 'too_many_requests', message: 'Too many login attempts' } },
});

module.exports = { baseLimiter, authLimiter };
