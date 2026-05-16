'use strict';

const admin = require('firebase-admin');
const config = require('../config');
const logger = require('../utils/logger');

let app;
function getApp() {
  if (app) return app;
  if (!config.firebase.projectId || !config.firebase.privateKey) return null;
  app = admin.initializeApp({
    credential: admin.credential.cert({
      projectId: config.firebase.projectId,
      clientEmail: config.firebase.clientEmail,
      privateKey: config.firebase.privateKey,
    }),
  });
  return app;
}

async function sendToTokens(tokens, { title, body, data }) {
  const a = getApp();
  if (!a || !tokens.length) {
    logger.debug({ tokens: tokens.length }, 'fcm.disabled_or_empty');
    return { sent: 0, failed: 0, disabled: !a };
  }
  const messaging = admin.messaging();
  const messages = tokens.map((token) => ({
    token,
    notification: { title, body },
    data: data ? Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) : undefined,
    android: { priority: 'high' },
    apns: { headers: { 'apns-priority': '10' } },
  }));
  const result = await messaging.sendEach(messages);
  return { sent: result.successCount, failed: result.failureCount, responses: result.responses };
}

module.exports = { sendToTokens };
