'use strict';

const prisma = require('../../database/prisma');
const exotel = require('../../services/exotel');
const config = require('../../config');
const { NotFound, BadRequest, Forbidden } = require('../../utils/errors');

async function listLeads({ user, q, status, ownerId, page = 1, pageSize = 25 }) {
  const where = {
    ...(status ? { status } : {}),
    ...(ownerId ? { ownerId } : {}),
    ...(user.role === 'TELECALLER' ? { ownerId: user.id } : {}),
    ...(q
      ? {
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q } },
            { company: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.lead.count({ where }),
    prisma.lead.findMany({
      where,
      orderBy: [{ nextFollowAt: 'asc' }, { updatedAt: 'desc' }],
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: { owner: { select: { id: true, name: true, avatarUrl: true } } },
    }),
  ]);
  return { total, page, pageSize, items };
}

async function getLead(id) {
  const lead = await prisma.lead.findUnique({
    where: { id },
    include: {
      owner: { select: { id: true, name: true, avatarUrl: true } },
      calls: { orderBy: { createdAt: 'desc' }, take: 50 },
    },
  });
  if (!lead) throw NotFound('Lead not found');
  return lead;
}

async function createLead(input, creator) {
  return prisma.lead.create({
    data: {
      name: input.name,
      phone: input.phone,
      company: input.company || null,
      email: input.email || null,
      status: input.status || 'NEW',
      ownerId: input.ownerId || creator.id,
      source: input.source || null,
      notes: input.notes || null,
      tags: input.tags || [],
      nextFollowAt: input.nextFollowAt ? new Date(input.nextFollowAt) : null,
    },
  });
}

async function updateLead(id, input, user) {
  const lead = await getLead(id);
  if (user.role === 'TELECALLER' && lead.ownerId !== user.id) throw Forbidden();
  const data = { ...input };
  if (data.nextFollowAt) data.nextFollowAt = new Date(data.nextFollowAt);
  return prisma.lead.update({ where: { id }, data });
}

async function clickToCall({ leadId, agent }) {
  const lead = await getLead(leadId);
  if (!lead.phone) throw BadRequest('Lead has no phone number');
  if (!agent.phone && !agent.email) throw BadRequest('Agent has no phone configured');

  const result = await exotel.connectCall({
    from: agent.phone,
    to: lead.phone,
    callerId: config.exotel.virtualNumber,
    statusCallback: config.exotel.callbackUrl,
  });

  const call = await prisma.telecallerCall.create({
    data: {
      leadId,
      agentId: agent.id,
      direction: 'OUTBOUND',
      externalCallId: result.Sid || result.sid || null,
      fromNumber: agent.phone,
      toNumber: lead.phone,
      status: result.Status || result.status || 'queued',
    },
  });

  await prisma.lead.update({
    where: { id: leadId },
    data: { status: lead.status === 'NEW' ? 'CONTACTED' : lead.status },
  });

  return { call, exotel: result };
}

async function handleWebhook(payload) {
  const sid = payload.CallSid || payload.sid;
  if (!sid) return null;
  return prisma.telecallerCall.updateMany({
    where: { externalCallId: sid },
    data: {
      status: payload.Status || payload.status,
      durationSec: payload.Duration ? parseInt(payload.Duration, 10) : undefined,
      recordingUrl: payload.RecordingUrl || undefined,
      startedAt: payload.StartTime ? new Date(payload.StartTime) : undefined,
      endedAt: payload.EndTime ? new Date(payload.EndTime) : undefined,
    },
  });
}

async function callHistory({ user, page = 1, pageSize = 50 }) {
  const where = user.role === 'TELECALLER' ? { agentId: user.id } : {};
  const [total, items] = await prisma.$transaction([
    prisma.telecallerCall.count({ where }),
    prisma.telecallerCall.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: {
        lead: { select: { id: true, name: true, company: true } },
        agent: { select: { id: true, name: true } },
      },
    }),
  ]);
  return { total, page, pageSize, items };
}

async function followupsDueToday(user) {
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(); end.setHours(23, 59, 59, 999);
  return prisma.lead.findMany({
    where: {
      ...(user.role === 'TELECALLER' ? { ownerId: user.id } : {}),
      nextFollowAt: { gte: start, lte: end },
    },
    orderBy: { nextFollowAt: 'asc' },
  });
}

module.exports = {
  listLeads,
  getLead,
  createLead,
  updateLead,
  clickToCall,
  handleWebhook,
  callHistory,
  followupsDueToday,
};
