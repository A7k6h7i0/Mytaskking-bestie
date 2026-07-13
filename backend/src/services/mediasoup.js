'use strict';

const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const config = require('../config');

function isConfigured() {
  return Boolean(config.mediasoup.connectApiUrl && config.mediasoup.socketUrl);
}

/** Stable numeric peer id for UI maps (replaces Agora uid). */
function toMediaPeerId(userId) {
  const numericUid = Number(userId);
  if (Number.isInteger(numericUid) && numericUid > 0) return numericUid;
  const hex = crypto.createHash('sha1').update(String(userId)).digest('hex').slice(0, 8);
  return (parseInt(hex, 16) % 2147483646) + 1;
}

async function ensureRoom(roomId) {
  const base = config.mediasoup.connectApiUrl.replace(/\/$/, '');
  const res = await fetch(`${base}/api/room`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ roomId }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`mediasoup room create failed (${res.status}): ${text}`);
  }
  return res.json();
}

function signJoinToken({ roomId, userId, userName }) {
  const secret = config.mediasoup.joinSecret;
  if (!secret) return null;
  const ttl = config.mediasoup.joinTokenTtlSeconds;
  return jwt.sign(
    { roomId, userId, userName, purpose: 'call-join' },
    secret,
    { expiresIn: ttl },
  );
}

/**
 * Media session payload returned to Flutter instead of Agora RTC token fields.
 * `channelName` is kept for backward-compatible client parsing.
 */
function generateMediaSession({ channelName, userId, userName, ttlSeconds }) {
  if (!isConfigured()) {
    return {
      mediaEngine: 'mediasoup',
      disabled: true,
      channelName,
      roomId: channelName,
      connectUrl: null,
      userName,
      joinToken: null,
      mediaPeerId: toMediaPeerId(userId),
      expiresAt: null,
    };
  }
  const ttl = ttlSeconds || config.mediasoup.joinTokenTtlSeconds;
  const expiresAt = Date.now() + ttl * 1000;
  return {
    mediaEngine: 'mediasoup',
    disabled: false,
    connectUrl: config.mediasoup.socketUrl,
    connectApiUrl: config.mediasoup.connectApiUrl,
    channelName,
    roomId: channelName,
    userName: userName || 'Participant',
    joinToken: signJoinToken({ roomId: channelName, userId, userName }),
    mediaPeerId: toMediaPeerId(userId),
    expiresAt,
  };
}

async function prepareCallRoom(channelName, userId, userName) {
  if (!isConfigured()) {
    return generateMediaSession({ channelName, userId, userName });
  }
  await ensureRoom(channelName);
  return generateMediaSession({ channelName, userId, userName });
}

module.exports = {
  isConfigured,
  toMediaPeerId,
  ensureRoom,
  generateMediaSession,
  prepareCallRoom,
};
