'use strict';

const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const crypto = require('node:crypto');
const config = require('../config');

function toAgoraUid(uid) {
  const numericUid = Number(uid);
  if (Number.isInteger(numericUid) && numericUid > 0) return numericUid;

  // Agora Web joins are more reliable with numeric RTC UIDs than arbitrary
  // account strings. Hash non-numeric ids into the positive 32-bit range and
  // reserve 0 because Agora treats it specially.
  const hex = crypto.createHash('sha1').update(String(uid)).digest('hex').slice(0, 8);
  const mapped = parseInt(hex, 16) % 2147483646;
  return mapped + 1;
}

function generateRtcToken({ channelName, uid, role = 'publisher', ttlSeconds }) {
  if (!config.agora.appId || !config.agora.appCertificate) {
    return { token: null, channelName, uid, expiresAt: null, disabled: true };
  }
  const ttl = ttlSeconds || config.agora.tokenTtlSeconds;
  const expireTime = Math.floor(Date.now() / 1000) + ttl;
  const rtcRole = role === 'subscriber' ? RtcRole.SUBSCRIBER : RtcRole.PUBLISHER;
  const tokenUid = toAgoraUid(uid);
  const token = RtcTokenBuilder.buildTokenWithUid(
    config.agora.appId,
    config.agora.appCertificate,
    channelName,
    tokenUid,
    rtcRole,
    expireTime
  );
  return { token, channelName, uid: tokenUid, expiresAt: expireTime * 1000, disabled: false, appId: config.agora.appId };
}

module.exports = { generateRtcToken };
