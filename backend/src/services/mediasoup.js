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

function connectBaseUrl() {
  return (config.mediasoup.connectApiUrl || '').replace(/\/$/, '');
}

/** Absolute URL for an SFU recording file path from calls.md (`/api/recordings/.../files/...`). */
function absoluteRecordingFileUrl(relativeOrAbsolute) {
  if (!relativeOrAbsolute) return null;
  const s = String(relativeOrAbsolute);
  if (/^https?:\/\//i.test(s)) return s;
  const base = connectBaseUrl();
  if (!base) return s;
  return `${base}${s.startsWith('/') ? s : `/${s}`}`;
}

/**
 * calls.md — GET /api/recordings
 * { success, count, recordings: [{ id, roomId, startTime, participants, files[] }] }
 */
async function listRecordings() {
  const base = connectBaseUrl();
  if (!base) return { success: false, count: 0, recordings: [] };
  const res = await fetch(`${base}/api/recordings`, {
    method: 'GET',
    headers: { Accept: 'application/json' },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`mediasoup list recordings failed (${res.status}): ${text}`);
  }
  const data = await res.json();
  const recordings = Array.isArray(data?.recordings) ? data.recordings : [];
  return {
    success: data?.success !== false,
    count: data?.count ?? recordings.length,
    recordings,
  };
}

async function deleteRecording(recordingId) {
  const base = connectBaseUrl();
  if (!base) throw new Error('mediasoup connect API not configured');
  const res = await fetch(
    `${base}/api/recordings/${encodeURIComponent(recordingId)}`,
    { method: 'DELETE', headers: { Accept: 'application/json' } },
  );
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`mediasoup delete recording failed (${res.status}): ${text}`);
  }
  return res.json().catch(() => ({ success: true, recordingId }));
}

module.exports = {
  isConfigured,
  toMediaPeerId,
  ensureRoom,
  generateMediaSession,
  prepareCallRoom,
  connectBaseUrl,
  absoluteRecordingFileUrl,
  listRecordings,
  deleteRecording,
};
