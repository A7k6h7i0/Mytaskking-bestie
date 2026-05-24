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
  const numericUid = Number(uid);
  const useNumericUid = Number.isInteger(numericUid) && String(numericUid) === String(uid);
  const tokenUid = useNumericUid ? numericUid : String(uid);
  const token = useNumericUid
    ? RtcTokenBuilder.buildTokenWithUid(
      config.agora.appId,
      config.agora.appCertificate,
      channelName,
      tokenUid,
      rtcRole,
      expireTime
    )
    : RtcTokenBuilder.buildTokenWithAccount(
      config.agora.appId,
      config.agora.appCertificate,
      channelName,
      String(uid),
      rtcRole,
      expireTime
    );
  return { token, channelName, uid: tokenUid, expiresAt: expireTime * 1000, disabled: false, appId: config.agora.appId };
}

module.exports = { generateRtcToken };
