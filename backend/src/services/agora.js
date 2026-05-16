'use strict';

const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const config = require('../config');

function generateRtcToken({ channelName, uid, role = 'publisher', ttlSeconds }) {
  if (!config.agora.appId || !config.agora.appCertificate) {
    return { token: null, channelName, uid, expiresAt: null, disabled: true };
  }
  const ttl = ttlSeconds || config.agora.tokenTtlSeconds;
  const expireTime = Math.floor(Date.now() / 1000) + ttl;
  const rtcRole = role === 'subscriber' ? RtcRole.SUBSCRIBER : RtcRole.PUBLISHER;
  const token = RtcTokenBuilder.buildTokenWithUid(
    config.agora.appId,
    config.agora.appCertificate,
    channelName,
    Number(uid) || 0,
    rtcRole,
    expireTime
  );
  return { token, channelName, uid, expiresAt: expireTime * 1000, disabled: false, appId: config.agora.appId };
}

module.exports = { generateRtcToken };
