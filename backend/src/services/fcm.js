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
  const isCallControl = stringData?.type === 'call.ended';
  const isActionableChat =
    (stringData?.type === 'chat.message' || stringData?.kind === 'CHAT' || stringData?.kind === 'MENTION') &&
    !!stringData?.channelId &&
    !!stringData?.actionToken;
  const isDataOnly = isCallLike || isCallControl || isActionableChat;
  const messages = tokens.map((token) => {
    const aps = { contentAvailable: true };
    if (!isCallControl) aps.sound = 'default';
    if (isDataOnly && !isCallControl) {
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
  // Prune tokens FCM reports as permanently dead (app uninstalled / token
  // rotated) so we don't keep pushing to them forever and piling up failures.
  try {
    const dead = [];
    result.responses.forEach((r, i) => {
      const code = r.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument'
      ) {
        dead.push(tokens[i]);
      }
    });
    if (dead.length) {
      // Lazy-require to avoid a circular import at module load.
      const prisma = require('../database/prisma');
      await prisma.deviceToken.deleteMany({ where: { token: { in: dead } } });
      logger.info({ pruned: dead.length }, 'fcm.dead_tokens_pruned');
    }
  } catch (err) {
    logger.warn({ err: err.message }, 'fcm.prune_failed');
  }
  return { sent: result.successCount, failed: result.failureCount, responses: result.responses };
}

async function sendCallEnded(call, clientApp) {
  if (!call?.id) return { sent: 0, failed: 0 };
  const userIds = [...new Set((call.participants || []).map((p) => p.userId).filter(Boolean))];
  if (!userIds.length) return { sent: 0, failed: 0 };
  const prisma = require('../database/prisma');
  const devices = await prisma.deviceToken.findMany({
    where: { userId: { in: userIds } },
    select: { token: true },
  });
  return sendToTokens(devices.map((d) => d.token), {
    title: 'Call ended',
    body: '',
    data: {
      type: 'call.ended',
      callId: call.id,
      ...(clientApp ? { clientApp } : {}),
    },
  });
}

module.exports = { sendToTokens, sendCallEnded };
