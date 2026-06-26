'use strict';

/** Client families that share the MyTaskKing backend but must not cross-notify. */
const APP_MYTASKKING = 'mytaskking';
const APP_WEB = 'web';

/** Legacy / sibling apps — never treat as this build. */
const BLOCKED_CLIENT_APPS = new Set([
  'mdl',
  'office_tracking',
  'office_tracking_app',
  'office-traking-app',
]);

function normalizeClientApp(value) {
  const app = (value || '').toString().trim().toLowerCase();
  if (!app || BLOCKED_CLIENT_APPS.has(app)) return null;
  if (app === APP_MYTASKKING || app === APP_WEB) return app;
  return null;
}

function clientAppFromUserAgent(ua) {
  const text = (ua || '').toString();
  if (/MDL-Mobile/i.test(text)) return null;
  if (/Office-Tracking-Mobile/i.test(text)) return null;
  if (/MyTaskKing-Mobile/i.test(text)) return APP_MYTASKKING;
  return APP_WEB;
}

function clientAppFromSocket(socket) {
  const fromAuth = normalizeClientApp(socket.handshake?.auth?.clientApp);
  if (fromAuth) return fromAuth;
  const ua = socket.handshake?.headers?.['user-agent'];
  return clientAppFromUserAgent(ua);
}

function userAppRoom(userId, clientApp) {
  return `user:${userId}:app:${clientApp || APP_WEB}`;
}

/** Broadcast to all sockets for the user, tagged with the originating app. */
function emitToUserApp(io, userId, clientApp, event, payload) {
  if (!io || !userId) return;
  io.to(`user:${userId}`).emit(event, {
    ...payload,
    clientApp: clientApp || APP_WEB,
  });
}

function emitToCallParticipants(io, call, event, payload, clientApp) {
  const body = {
    ...payload,
    ...(clientApp ? { clientApp } : {}),
  };
  for (const p of call?.participants || []) {
    io?.to(`user:${p.userId}`).emit(event, body);
  }
}

module.exports = {
  APP_MYTASKKING,
  APP_WEB,
  clientAppFromUserAgent,
  clientAppFromSocket,
  userAppRoom,
  emitToUserApp,
  emitToCallParticipants,
};
