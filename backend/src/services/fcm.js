'use strict';

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const config = require('../config');
const logger = require('../utils/logger');

let app;
let initFailed = false;

function getApp() {
  if (app) return app;
  if (initFailed) return null;

  try {
    let credential;
    if (config.firebase.serviceAccountPath) {
      const serviceAccountPath = path.resolve(config.firebase.serviceAccountPath);
      const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
      credential = admin.credential.cert(serviceAccount);
    } else if (config.firebase.projectId && config.firebase.clientEmail && config.firebase.privateKey) {
      credential = admin.credential.cert({
        projectId: config.firebase.projectId,
        clientEmail: config.firebase.clientEmail,
        privateKey: config.firebase.privateKey,
      });
    }

    if (!credential) return null;
    app = admin.initializeApp({ credential });
    return app;
  } catch (err) {
    initFailed = true;
    logger.warn({ err: err.message }, 'fcm.init_failed');
    return null;
  }
}

async function sendToTokens(tokens, { title, body, data }) {
  const a = getApp();
  if (!a || !tokens.length) {
    logger.debug({ tokens: tokens.length }, 'fcm.disabled_or_empty');
    return { sent: 0, failed: 0, disabled: !a };
  }
  const messaging = admin.messaging();
  const stringData = data
    ? Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)]))
    : undefined;
  const isCallLike = stringData?.type === 'call.incoming' || stringData?.type === 'meeting.invited';
  const isActionableChat =
    (stringData?.type === 'chat.message' || stringData?.kind === 'CHAT' || stringData?.kind === 'MENTION') &&
    !!stringData?.channelId &&
    !!stringData?.actionToken;
  const isDataOnly = isCallLike || isActionableChat;
  const messages = tokens.map((token) => {
    const aps = { sound: 'default', contentAvailable: true };
    if (isDataOnly) {
      if (isCallLike) aps.category = 'CALL_INVITE';
      aps.alert = { title, body };
    }
    const androidNotification = {
      priority: isCallLike ? 'max' : 'high',
      visibility: 'public',
      sound: 'default',
      clickAction: 'FLUTTER_NOTIFICATION_CLICK',
    };
    if (isCallLike) androidNotification.channelId = 'calls';
    const message = {
      token,
      notification: isDataOnly ? undefined : { title, body },
      data: isDataOnly
        ? { ...(stringData || {}), title: String(title || ''), body: String(body || '') }
        : stringData,
      android: {
        priority: 'high',
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps },
      },
    };
    if (isDataOnly) delete message.notification;
    else message.android.notification = androidNotification;
    return message;
  });
  const result = await messaging.sendEach(messages);
  return { sent: result.successCount, failed: result.failureCount, responses: result.responses };
}

module.exports = { sendToTokens };
