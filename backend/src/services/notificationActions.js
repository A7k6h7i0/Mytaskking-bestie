'use strict';

const jwt = require('jsonwebtoken');
const config = require('../config');
const { Unauthorized, BadRequest } = require('../utils/errors');

const ISSUER = 'bestie-notification-actions';

function publicApiBaseUrl() {
  const trimmed = String(config.publicApiUrl || '').replace(/\/$/, '');
  return trimmed.endsWith('/api/v1') ? trimmed : `${trimmed}/api/v1`;
}

function signAction(payload, expiresIn = '2m') {
  if (!payload?.action || !payload?.userId) {
    throw BadRequest('Invalid notification action payload');
  }
  return jwt.sign(payload, config.jwt.accessSecret, {
    expiresIn,
    issuer: ISSUER,
  });
}

function verifyAction(token, expectedAction) {
  try {
    const payload = jwt.verify(token, config.jwt.accessSecret, {
      issuer: ISSUER,
    });
    if (expectedAction && payload.action !== expectedAction) {
      throw Unauthorized('Wrong notification action');
    }
    return payload;
  } catch (_) {
    throw Unauthorized('Invalid or expired notification action');
  }
}

module.exports = {
  publicApiBaseUrl,
  signAction,
  verifyAction,
};
