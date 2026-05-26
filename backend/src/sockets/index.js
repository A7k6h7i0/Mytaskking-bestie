'use strict';

const { Server } = require('socket.io');
const config = require('../config');
const logger = require('../utils/logger');
const prisma = require('../database/prisma');
const { verifyAccessToken } = require('../services/tokens');
const monitoring = require('../services/monitoring');
const cache = require('../services/cache');
const chatService = require('../modules/chat/chat.service');

const presence = new Map(); // userId -> Set<socketId>

function broadcastPresence(io, userId, online, lastSeenAt = new Date()) {
  io.emit('presence.update', { userId, online, lastSeenAt });
}

module.exports = function initSockets(server) {
  const io = new Server(server, {
    cors: { origin: config.cors.webOrigin, credentials: true },
    path: '/socket.io',
  });

  // Cluster across instances when Redis is configured. Without this, each
  // Node process only fans events to its own connected sockets — fine for
  // single-instance, broken behind a load balancer.
  if (cache.redis()) {
    try {
      const { createAdapter } = require('@socket.io/redis-adapter');
      const pub = cache.redis().duplicate();
      const sub = cache.redis().duplicate();
      io.adapter(createAdapter(pub, sub));
      logger.info('socket.io.redis_adapter.ready');
    } catch (err) {
      logger.warn({ err: err.message }, 'socket.io.redis_adapter.failed — single-instance fanout only');
    }
  }

  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) return next(new Error('unauthorized'));
      const payload = verifyAccessToken(token);
      const user = await prisma.user.findUnique({ where: { id: payload.sub } });
      if (!user || user.status !== 'ACTIVE') return next(new Error('unauthorized'));
      if (user.isClient && user.accessEndsAt && user.accessEndsAt < new Date()) {
        return next(new Error('gone'));
      }
      socket.user = user;
      next();
    } catch (e) {
      next(new Error('unauthorized'));
    }
  });

  io.on('connection', async (socket) => {
    monitoring.trackSocketConnect();
    const userId = socket.user.id;
    socket.join(`user:${userId}`);

    const connectedAt = new Date();
    if (!presence.has(userId)) {
      presence.set(userId, new Set());
      broadcastPresence(io, userId, true, connectedAt);
      cache.set(`presence:online:${userId}`, true).catch(() => {});
    }
    presence.get(userId).add(socket.id);

    await prisma.user.update({ where: { id: userId }, data: { lastSeenAt: connectedAt } }).catch(() => {});

    // Auto-join all my channel rooms so I receive realtime messages.
    const memberships = await prisma.channelMember.findMany({ where: { userId } });
    for (const m of memberships) socket.join(`channel:${m.channelId}`);
    chatService
      .markDeliveredForUser({
        userId,
        channelIds: memberships.map((m) => m.channelId),
      })
      .then((groups) => {
        for (const group of groups) {
          io.to(`channel:${group.channelId}`).emit('chat.message.receipts.bulk', {
            channelId: group.channelId,
            userId,
            state: 'DELIVERED',
            messageIds: group.messageIds,
          });
        }
      })
      .catch(() => {});

    socket.on('channel.join', (channelId) => socket.join(`channel:${channelId}`));
    socket.on('channel.leave', (channelId) => socket.leave(`channel:${channelId}`));

    socket.on('chat.typing', ({ channelId, typing, threadRootId }) => {
      socket.to(`channel:${channelId}`).emit('chat.typing', {
        channelId,
        threadRootId: threadRootId || null,
        userId,
        userName: socket.user.name,
        isClient: socket.user.isClient,
        typing: !!typing,
      });
    });

    // Lightweight client-driven presence status — persisted by REST, but the
    // realtime burst goes here so peers see status changes immediately.
    socket.on('presence.set', ({ status, customStatus }) => {
      io.emit('presence.status', {
        userId,
        status: status || 'ACTIVE',
        customStatus: customStatus || null,
      });
    });

    // --- collaboration rooms (cursors, shared ops) — yjs-compatible shape ---
    // Per-document rooms so the same socket can participate in many docs at
    // once. Cursors fan out via `collab.presence`, opaque ops via `collab.op`.
    // When you swap in yjs, replace this with a y-websocket relay; client API
    // (services/collab.ts) stays the same.
    socket.on('collab.join', ({ roomId, user }) => {
      if (!roomId) return;
      socket.join(`collab:${roomId}`);
      io.in(`collab:${roomId}`).emit('collab.presence', {
        roomId,
        peers: [{ userId: user?.id || userId, name: user?.name || socket.user.name }],
      });
    });
    socket.on('collab.leave', ({ roomId }) => {
      if (roomId) socket.leave(`collab:${roomId}`);
    });
    socket.on('collab.cursor', ({ roomId, cursor }) => {
      if (!roomId) return;
      socket.to(`collab:${roomId}`).emit('collab.presence', {
        roomId,
        peers: [{ userId, name: socket.user.name, cursor }],
      });
    });
    socket.on('collab.op', ({ roomId, op }) => {
      if (!roomId) return;
      socket.to(`collab:${roomId}`).emit('collab.op', { roomId, from: userId, op });
    });

    // Call signaling (Agora handles media; sockets carry signaling)
    socket.on('call.signal', ({ to, payload }) => {
      if (!to) return;
      io.to(`user:${to}`).emit('call.signal', { from: userId, payload });
    });

    socket.on('call.ringing.ack', ({ callId }) => {
      io.emit('call.ringing.ack', { callId, userId });
    });

    socket.on('disconnect', () => {
      monitoring.trackSocketDisconnect();
      const set = presence.get(userId);
      if (set) {
        set.delete(socket.id);
        if (set.size === 0) {
          presence.delete(userId);
          const lastSeenAt = new Date();
          broadcastPresence(io, userId, false, lastSeenAt);
          prisma.user.update({ where: { id: userId }, data: { lastSeenAt } }).catch(() => {});
          cache.del(`presence:online:${userId}`).catch(() => {});
        }
      }
    });
  });

  logger.info('socket.io.ready');
  return io;
};
