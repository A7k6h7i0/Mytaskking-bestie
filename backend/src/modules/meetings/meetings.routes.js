'use strict';

const { Router } = require('express');
const Joi = require('joi');
const { nanoid } = require('nanoid');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const agora = require('../../services/agora');
const mediasoup = require('../../services/mediasoup');
const audit = require('../../services/audit');
const eventBus = require('../../services/eventBus');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const config = require('../../config');
const { clientAppFromUserAgent, APP_MYTASKKING } = require('../../utils/clientApp');

const router = Router();

/** Socket + FCM ring for meeting invites (same UX as incoming call). */
function notifyMeetingInvited(io, { room, host, userIds, clientApp }) {
  const ids = Array.from(new Set((userIds || []).filter(Boolean)));
  if (!ids.length) return;
  const app = clientApp || APP_MYTASKKING;
  const payload = {
    meeting: {
      id: room.id,
      slug: room.slug,
      name: room.name,
      mode: room.mode,
      host: {
        id: host.id,
        name: host.name,
        avatarUrl: host.avatarUrl,
      },
    },
    clientApp: app,
  };
  for (const uid of ids) {
    io?.to(`user:${uid}`).emit('meeting.invited', payload);
  }
  prisma.deviceToken
    .findMany({ where: { userId: { in: ids } } })
    .then((devices) => {
      if (!devices.length) return null;
      return require('../../services/fcm').sendToTokens(
        devices.map((d) => d.token),
        {
          title: `${host.name || 'Someone'} invited you to a meeting`,
          body: room.name,
          data: {
            type: 'meeting.invited',
            meetingSlug: room.slug,
            mode: room.mode || 'VIDEO',
            fromName: host.name || 'Someone',
            clientApp: app,
          },
        }
      );
    })
    .catch(() => {});
}

const Mode = Joi.string().valid('VOICE', 'VIDEO', 'WEBINAR', 'LIVESTREAM');
const PUBLIC_BASE_URL = process.env.MEETING_PUBLIC_URL || config.cors.webOrigin?.[0] || 'http://localhost:5173';

function serializeRoom(room) {
  if (!room) return room;
  const rest = { ...room };
  delete rest.participants;
  delete rest.shareEvents;
  delete rest.guestRequests;
  return {
    ...rest,
    shareUrl: `${PUBLIC_BASE_URL.replace(/\/$/, '')}/meetings/join/${rest.slug}`,
  };
}

function canManageRoom(room, user) {
  return room.hostId === user.id || ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
}

/** Host, explicit invitee, or already-joined participant — not any logged-in user. */
async function assertCanJoinMeeting(room, user) {
  if (canManageRoom(room, user)) return;
  if (room.hostId === user.id) return;
  const row = await prisma.meetingRoomParticipant.findFirst({
    where: { roomId: room.id, userId: user.id },
    select: { id: true },
  });
  if (!row) {
    throw Forbidden('You are not invited to this meeting');
  }
}

async function recordParticipant({ room, userId = null, displayName, joinedVia }) {
  if (userId) {
    const existing = await prisma.meetingRoomParticipant.findFirst({
      where: { roomId: room.id, userId },
    });
    if (existing) {
      // Token / guest join upgrades INVITED → INTERNAL so the live roster
      // can tell invitees who actually entered the Agora channel.
      return prisma.meetingRoomParticipant.update({
        where: { id: existing.id },
        data: {
          lastSeenAt: new Date(),
          displayName,
          joinedVia: joinedVia || existing.joinedVia,
        },
      });
    }
  }

  return prisma.meetingRoomParticipant.create({
    data: {
      roomId: room.id,
      userId,
      displayName,
      joinedVia,
    },
  });
}

async function meetingNotifyUserIds(room) {
  const targets = new Set([room.hostId].filter(Boolean));
  if (Array.isArray(room._notifyUserIds)) {
    for (const uid of room._notifyUserIds) {
      if (uid) targets.add(uid);
    }
  } else {
    const rows = await prisma.meetingRoomParticipant.findMany({
      where: { roomId: room.id, userId: { not: null } },
      select: { userId: true },
    });
    for (const row of rows) {
      if (row.userId) targets.add(row.userId);
    }
  }
  return targets;
}

function notifyMeetingJoin(io, room, participant) {
  const payload = {
    roomId: room.id,
    slug: room.slug,
    name: room.name,
    participant: {
      id: participant.id,
      displayName: participant.displayName,
      joinedVia: participant.joinedVia,
      joinedAt: participant.joinedAt,
      userId: participant.userId,
      agoraUid: participant.userId
        ? agora.toAgoraUid(participant.userId)
        : null,
    },
  };
  // Prefer precomputed notify set from token handler; otherwise fire-and-forget.
  Promise.resolve(meetingNotifyUserIds(room)).then((targets) => {
    for (const uid of targets) {
      if (uid === participant.userId) continue;
      io?.to(`user:${uid}`).emit('meeting.participant.joined', payload);
    }
  }).catch(() => {});
}

async function notifyMeetingLeft(io, room, { userId, displayName }) {
  const payload = {
    roomId: room.id,
    slug: room.slug,
    participant: {
      userId,
      displayName: displayName || 'Participant',
      agoraUid: userId ? agora.toAgoraUid(userId) : null,
    },
  };
  const targets = await meetingNotifyUserIds(room);
  for (const uid of targets) {
    if (uid === userId) continue;
    io?.to(`user:${uid}`).emit('meeting.participant.left', payload);
  }
}

async function notifyMeetingEnded(io, room, extra = {}) {
  const payload = {
    slug: room.slug,
    meetingId: room.id,
    ...extra,
  };
  const targets = await meetingNotifyUserIds(room);
  for (const uid of targets) {
    io?.to(`user:${uid}`).emit('meeting.ended', payload);
  }
}

function serializeMeetingRoster(participants = []) {
  return participants
    .filter((p) => p && p.userId)
    .filter((p) => {
      // Only people who actually entered via token/guest join.
      // INVITED rows have lastSeenAt defaulting to now() — never treat that
      // as "in meeting" or clients show ghost guests when alone.
      const via = String(p.joinedVia || '');
      return via === 'INTERNAL' || via === 'GUEST';
    })
    .map((p) => ({
      id: p.id,
      userId: p.userId,
      displayName: p.displayName || 'Participant',
      joinedVia: p.joinedVia,
      joinedAt: p.joinedAt,
      lastSeenAt: p.lastSeenAt || null,
      agoraUid: agora.toAgoraUid(p.userId),
    }));
}

router.get(
  '/public/:slug',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    res.json(serializeRoom(room));
  })
);

router.get(
  '/public/:slug/lobby',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({
      where: { slug: req.params.slug },
      include: {
        participants: { orderBy: { joinedAt: 'desc' }, take: 20 },
        shareEvents: { orderBy: { copiedAt: 'desc' }, take: 20 },
        guestRequests: {
          where: { status: 'PENDING' },
          orderBy: { requestedAt: 'desc' },
          take: 20,
        },
      },
    });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    res.json({
      room: serializeRoom(room),
      participants: room.participants,
      shareHistory: room.shareEvents,
      pendingRequests: room.guestRequests.map((request) => ({
        id: request.id,
        guestName: request.guestName,
        requestedAt: request.requestedAt,
        status: request.status,
      })),
    });
  })
);

router.post(
  '/public/:slug/share',
  validate({
    body: Joi.object({
      copiedByName: Joi.string().trim().min(2).max(120).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const share = await prisma.meetingRoomShareEvent.create({
      data: {
        roomId: room.id,
        copiedByName: req.body.copiedByName.trim(),
      },
    });
    res.json(share);
  })
);

router.post(
  '/public/:slug/request-access',
  validate({
    body: Joi.object({
      guestName: Joi.string().trim().min(2).max(120).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const guestUid = `guest_${nanoid(12)}`;
    const request = await prisma.meetingRoomGuestRequest.create({
      data: {
        roomId: room.id,
        guestName: req.body.guestName.trim(),
        guestUid,
      },
    });
    req.app.get('io')?.to(`user:${room.hostId}`).emit('meeting.guest_request.created', {
      roomId: room.id,
      slug: room.slug,
      requestId: request.id,
      guestName: request.guestName,
    });
    res.status(201).json({
      requestId: request.id,
      status: request.status,
      guestName: request.guestName,
      requestedAt: request.requestedAt,
    });
  })
);

router.get(
  '/public/:slug/request-access/:requestId',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const request = await prisma.meetingRoomGuestRequest.findFirst({
      where: { id: req.params.requestId, roomId: room.id },
    });
    if (!request) throw NotFound('Guest request not found');
    res.json({
      requestId: request.id,
      status: request.status,
      guestName: request.guestName,
      requestedAt: request.requestedAt,
      reviewedAt: request.reviewedAt,
    });
  })
);

router.post(
  '/public/:slug/token',
  validate({
    body: Joi.object({
      guestName: Joi.string().trim().min(2).max(120).required(),
      requestId: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const guestName = req.body.guestName.trim();
    // Knock first — guests cannot silently mint a media session.
    const request = await prisma.meetingRoomGuestRequest.findFirst({
      where: { id: req.body.requestId, roomId: room.id },
    });
    if (!request) throw NotFound('Guest request not found');
    if (request.status !== 'APPROVED') {
      throw Forbidden('Host has not approved your join request yet');
    }
    if (request.guestName.trim().toLowerCase() !== guestName.toLowerCase()) {
      throw BadRequest('Guest name does not match the approved request');
    }
    const guestUid = request.guestUid || `guest_${nanoid(12)}`;
    const media = await mediasoup.prepareCallRoom(
      room.channelName,
      guestUid,
      guestName
    );
    const participant = await recordParticipant({
      room,
      displayName: guestName,
      joinedVia: 'GUEST',
    }).catch(() => null);
    if (participant) {
      const rosterRows = await prisma.meetingRoomParticipant.findMany({
        where: { roomId: room.id, userId: { not: null } },
        select: { userId: true },
      });
      room._notifyUserIds = rosterRows.map((r) => r.userId).filter(Boolean);
      notifyMeetingJoin(req.app.get('io'), room, participant);
    }
    res.json({
      ...media,
      // Keep legacy field names some web clients still read.
      uid: media.mediaPeerId,
      appId: null,
      token: media.joinToken,
      mode: room.mode,
      guestName,
      room: serializeRoom({ id: room.id, slug: room.slug, name: room.name, mode: room.mode }),
    });
  })
);

router.use(requireAuth);

router.get(
  '/',
  validate({
    query: Joi.object({
      includeEnded: Joi.alternatives().try(Joi.boolean(), Joi.string().valid('1', '0', 'true', 'false')),
    }),
  }),
  asyncHandler(async (req, res) => {
    // Show meetings the user is hosting OR has been explicitly invited to
    // (via participantIds at create time). Random members of the tenant no
    // longer see other people's rooms.
    const includeEndedRaw = req.query.includeEnded;
    const includeEnded =
      includeEndedRaw === true ||
      includeEndedRaw === '1' ||
      includeEndedRaw === 'true';
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const access = {
      OR: [
        { hostId: req.user.id },
        { participants: { some: { userId: req.user.id } } },
      ],
    };
    const where = includeEnded
      ? {
          AND: [
            access,
            {
              OR: [
                { endedAt: null },
                { endedAt: { gte: since } },
              ],
            },
          ],
        }
      : { endedAt: null, ...access };
    const items = await prisma.meetingRoom.findMany({
      where,
      orderBy: [{ endedAt: 'asc' }, { createdAt: 'desc' }],
      include: {
        participants: {
          where: {
            userId: { not: null },
            joinedVia: { in: ['INTERNAL', 'GUEST'] },
          },
          select: { id: true },
        },
        guestRequests: {
          where: { status: 'PENDING' },
          select: { id: true },
        },
      },
    });
    res.json({
      items: items.map((room) => ({
        ...serializeRoom(room),
        pendingGuestCount: room.guestRequests.length,
        // Live people only — not INVITED / LEFT rows.
        participantCount: room.participants.length,
      })),
    });
  })
);

router.get(
  '/:slug/guest-requests',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (room.endedAt) throw BadRequest('Meeting has ended');
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const items = await prisma.meetingRoomGuestRequest.findMany({
      where: { roomId: room.id },
      orderBy: [{ status: 'asc' }, { requestedAt: 'desc' }],
      take: 50,
    });
    res.json({ items });
  })
);

router.post(
  '/:slug/guest-requests/:requestId/approve',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const request = await prisma.meetingRoomGuestRequest.update({
      where: { id: req.params.requestId },
      data: {
        status: 'APPROVED',
        approvedAt: new Date(),
        reviewedAt: new Date(),
        reviewedById: req.user.id,
        rejectedAt: null,
      },
    });
    req.app.get('io')?.to(`user:${room.hostId}`).emit('meeting.guest_request.approved', {
      roomId: room.id,
      requestId: request.id,
      guestName: request.guestName,
    });
    res.json(request);
  })
);

router.post(
  '/:slug/guest-requests/:requestId/reject',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const request = await prisma.meetingRoomGuestRequest.update({
      where: { id: req.params.requestId },
      data: {
        status: 'REJECTED',
        rejectedAt: new Date(),
        reviewedAt: new Date(),
        reviewedById: req.user.id,
        approvedAt: null,
      },
    });
    req.app.get('io')?.to(`user:${room.hostId}`).emit('meeting.guest_request.rejected', {
      roomId: room.id,
      requestId: request.id,
      guestName: request.guestName,
    });
    res.json(request);
  })
);

router.post(
  '/:slug/share',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    const share = await prisma.meetingRoomShareEvent.create({
      data: {
        roomId: room.id,
        copiedById: req.user.id,
        copiedByName: req.user.name,
      },
    });
    res.json(share);
  })
);

router.post(
  '/:slug/participants',
  validate({
    body: Joi.object({
      participantIds: Joi.array().items(Joi.string()).min(1).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room || room.endedAt) throw NotFound('Meeting not found');
    if (!canManageRoom(room, req.user)) throw Forbidden();

    const requestedIds = Array.from(new Set(
      req.body.participantIds
        .map((uid) => String(uid || '').trim())
        .filter((uid) => uid && uid !== req.user.id)
    ));
    if (!requestedIds.length) throw BadRequest('Need at least one participant');

    const existing = await prisma.meetingRoomParticipant.findMany({
      where: { roomId: room.id, userId: { in: requestedIds } },
      select: { userId: true, joinedVia: true },
    });
    const existingByUser = new Map(existing.map((p) => [p.userId, p]));

    // New invitees + re-ring people still only INVITED (they often missed the
    // first push). Skip people who already joined (INTERNAL / GUEST).
    const toCreateIds = [];
    const toNotifyIds = [];
    for (const uid of requestedIds) {
      const row = existingByUser.get(uid);
      if (!row) {
        toCreateIds.push(uid);
        toNotifyIds.push(uid);
      } else if (String(row.joinedVia || '') === 'INVITED') {
        toNotifyIds.push(uid);
      }
    }

    // Resolve by id only (same as meeting create). A strict tenantId filter
    // previously dropped invitees when room.tenantId was null/mismatched.
    const users = toNotifyIds.length
      ? await prisma.user.findMany({
          where: { id: { in: toNotifyIds } },
          select: { id: true, name: true },
        })
      : [];
    const userById = new Map(users.map((u) => [u.id, u]));

    const createUsers = toCreateIds.map((id) => userById.get(id)).filter(Boolean);
    if (createUsers.length) {
      await prisma.meetingRoomParticipant.createMany({
        data: createUsers.map((u) => ({
          roomId: room.id,
          userId: u.id,
          displayName: u.name || 'Invited',
          joinedVia: 'INVITED',
        })),
        skipDuplicates: true,
      });
    }

    const notifyIds = users.map((u) => u.id);
    if (notifyIds.length) {
      notifyMeetingInvited(req.app.get('io'), {
        room,
        host: req.user,
        userIds: notifyIds,
        clientApp:
          clientAppFromUserAgent(req.headers['user-agent']) || APP_MYTASKKING,
      });
    }

    const refreshed = await prisma.meetingRoom.findUnique({
      where: { id: room.id },
      include: { _count: { select: { participants: true } } },
    });
    res.json({
      room: serializeRoom(refreshed),
      invited: users.map((u) => ({ id: u.id, name: u.name })),
      skipped: requestedIds.length - notifyIds.length,
    });
  })
);

router.post(
  '/',
  validate({
    body: Joi.object({
      name: Joi.string().min(1).max(180).required(),
      mode: Mode.default('VIDEO'),
      scheduledAt: Joi.alternatives()
        .try(Joi.valid(null), Joi.date().iso().greater('now'))
        .optional(),
      participantIds: Joi.array().items(Joi.string()),
    }),
  }),
  asyncHandler(async (req, res) => {
    let scheduledAt = null;
    if (req.body.scheduledAt) {
      scheduledAt = new Date(req.body.scheduledAt);
      if (Number.isNaN(scheduledAt.getTime()) || scheduledAt.getTime() < Date.now() - 30_000) {
        throw BadRequest('Meeting cannot be scheduled in the past');
      }
    }
    const slug = nanoid(10);
    const room = await prisma.meetingRoom.create({
      data: {
        slug,
        name: req.body.name,
        mode: req.body.mode,
        channelName: `meet_${slug}`,
        hostId: req.user.id,
        scheduledAt,
        tenantId: req.user.tenantId || null,
      },
    });
    audit.record({ kind: 'meeting.created', entity: 'meeting', entityId: room.id, payload: { mode: room.mode }, req });
    await eventBus.publish('meeting.created', { meetingId: room.id, mode: room.mode }, { tenantId: room.tenantId });

    // Host as INVITED until first real token join — otherwise auto-end never
    // fires (ghost INTERNAL host keeps active count >= 1 forever).
    await prisma.meetingRoomParticipant.create({
      data: {
        roomId: room.id,
        userId: req.user.id,
        displayName: req.user.name || 'Host',
        joinedVia: 'INVITED',
      },
    }).catch(() => {});

    // Ring the invitees in real time + FCM push so they get a meeting
    // preview (like an incoming call) even if the app is backgrounded.
    const inviteeIds = Array.isArray(req.body.participantIds)
      ? req.body.participantIds.filter((uid) => uid && uid !== req.user.id)
      : [];
    if (inviteeIds.length) {
      // Persist invitations so `/meetings` only surfaces the room to the
      // people who were actually invited (plus the host). joinedVia tags
      // them as not-yet-joined; recordParticipant flips it on real join.
      const lookup = await prisma.user.findMany({
        where: { id: { in: inviteeIds } },
        select: { id: true, name: true },
      });
      if (lookup.length) {
        await prisma.meetingRoomParticipant.createMany({
          data: lookup.map((u) => ({
            roomId: room.id,
            userId: u.id,
            displayName: u.name || 'Invited',
            joinedVia: 'INVITED',
          })),
          skipDuplicates: true,
        });
        notifyMeetingInvited(req.app.get('io'), {
          room,
          host: req.user,
          userIds: lookup.map((u) => u.id),
          clientApp:
            clientAppFromUserAgent(req.headers['user-agent']) || APP_MYTASKKING,
        });
      }
    }
    res.status(201).json(serializeRoom(room));
  })
);

router.get(
  '/:slug',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    res.json(serializeRoom(room));
  })
);

router.post(
  '/:slug/token',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    if (room.endedAt) throw BadRequest('Meeting has ended');
    await assertCanJoinMeeting(room, req.user);

    // Meetings use the same mediasoup SFU as 1:1 calls (connect.mytaskking.com).
    const media = await mediasoup.prepareCallRoom(
      room.channelName,
      req.user.id,
      req.user.name
    );
    const participant = await recordParticipant({
      room,
      userId: req.user.id,
      displayName: req.user.name,
      joinedVia: 'INTERNAL',
    });

    const rosterRows = await prisma.meetingRoomParticipant.findMany({
      where: { roomId: room.id, userId: { not: null } },
      orderBy: { joinedAt: 'desc' },
      take: 100,
    });
    room._notifyUserIds = rosterRows.map((r) => r.userId).filter(Boolean);

    // Always fan out — including host join — so invitees already in the room
    // get roster + mediasoup uid mapping without waiting on SFU alone.
    notifyMeetingJoin(req.app.get('io'), room, participant);

    res.json({
      ...media,
      uid: media.mediaPeerId,
      appId: null,
      token: media.joinToken,
      mode: room.mode,
      room: serializeRoom({
        id: room.id,
        slug: room.slug,
        name: room.name,
        mode: room.mode,
        hostId: room.hostId,
      }),
      // Live roster so Flutter can map peer id → name without call.announce.
      participants: serializeMeetingRoster(rosterRows),
    });
  })
);

router.post(
  '/:slug/end',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) return res.status(204).end();
    if (!canManageRoom(room, req.user)) throw Forbidden();
    const updated = await prisma.meetingRoom.update({ where: { id: room.id }, data: { endedAt: new Date() } });
    audit.record({ kind: 'meeting.ended', entity: 'meeting', entityId: room.id, req });
    await eventBus.publish('meeting.ended', { meetingId: room.id }, { tenantId: room.tenantId });
    await notifyMeetingEnded(req.app.get('io'), room);
    res.json(updated);
  })
);

/**
 * Leave a live meeting. When the last INTERNAL/GUEST participant exits
 * (everyone including the host), the meeting auto-ends — no End button needed.
 */
router.post(
  '/:slug/leave',
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) return res.json({ ok: true, ended: true });
    if (room.endedAt) return res.json({ ok: true, ended: true });

    const membership = await prisma.meetingRoomParticipant.findFirst({
      where: { roomId: room.id, userId: req.user.id },
    });
    if (!membership && room.hostId !== req.user.id) {
      throw Forbidden('Not a participant');
    }

    const wasLive =
      membership &&
      ['INTERNAL', 'GUEST'].includes(String(membership.joinedVia || ''));

    if (wasLive) {
      await prisma.meetingRoomParticipant.update({
        where: { id: membership.id },
        data: { joinedVia: 'LEFT', lastSeenAt: new Date() },
      });
    } else if (membership && membership.joinedVia === 'INVITED') {
      // Invitee never entered media — no live presence to clear.
    }

    // Snapshot notify targets before we treat this user as gone.
    const rosterRows = await prisma.meetingRoomParticipant.findMany({
      where: { roomId: room.id, userId: { not: null } },
      select: { userId: true },
    });
    room._notifyUserIds = rosterRows.map((r) => r.userId).filter(Boolean);

    if (wasLive) {
      await notifyMeetingLeft(req.app.get('io'), room, {
        userId: req.user.id,
        displayName: membership.displayName || req.user.name,
      });
    }

    const active = await prisma.meetingRoomParticipant.count({
      where: {
        roomId: room.id,
        userId: { not: null },
        joinedVia: { in: ['INTERNAL', 'GUEST'] },
      },
    });

    let ended = false;
    if (active === 0) {
      await prisma.meetingRoom.update({
        where: { id: room.id },
        data: { endedAt: new Date() },
      });
      ended = true;
      audit.record({
        kind: 'meeting.ended',
        entity: 'meeting',
        entityId: room.id,
        payload: { reason: 'empty_room' },
        req,
      });
      await eventBus.publish(
        'meeting.ended',
        { meetingId: room.id, reason: 'empty_room' },
        { tenantId: room.tenantId }
      );
      await notifyMeetingEnded(req.app.get('io'), room, { reason: 'empty_room' });
    }

    res.json({ ok: true, ended, activeParticipants: active });
  })
);

// Attach a client-recorded file (uploaded as a FileAsset) to the meeting so
// it shows up in the admin recordings panel.
router.post(
  '/:slug/recording',
  validate({
    body: Joi.object({
      fileId: Joi.string().allow(null, ''),
      url: Joi.string().allow(null, ''),
    }),
  }),
  asyncHandler(async (req, res) => {
    const room = await prisma.meetingRoom.findUnique({ where: { slug: req.params.slug } });
    if (!room) throw NotFound('Meeting not found');
    // Only the host/admin or an actual participant may attach a recording —
    // otherwise any authenticated user could overwrite a meeting's recording
    // just by knowing its slug.
    if (!canManageRoom(room, req.user)) {
      const participant = await prisma.meetingRoomParticipant.findFirst({
        where: { roomId: room.id, userId: req.user.id },
      });
      if (!participant) throw Forbidden();
    }
    let url = req.body.url || null;
    if (!url && req.body.fileId) {
      const file = await prisma.fileAsset.findUnique({ where: { id: req.body.fileId } });
      url = file?.url || null;
    }
    if (!url) throw BadRequest('Recording url required');
    const updated = await prisma.meetingRoom.update({
      where: { id: room.id },
      data: { recordingUrl: url },
    });
    audit.record({ kind: 'meeting.recording.saved', entity: 'meeting', entityId: room.id, payload: { url }, req });
    res.json({ ok: true, recordingUrl: updated.recordingUrl });
  })
);

module.exports = router;
