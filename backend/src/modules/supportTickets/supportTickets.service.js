'use strict';

const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');

const ISSUE_TYPE_LABELS = {
  APP_CRASH: 'App crash or freeze',
  LOGIN_ACCESS: 'Login or access',
  CALLS_MEETINGS: 'Calls or meetings',
  CHAT_MESSAGES: 'Chat or messages',
  TASKS_REPORTS: 'Tasks or reports',
  BILLING_SUBSCRIPTION: 'Billing or subscription',
  OTHER: 'Other',
};

const STATUS_LABELS = {
  OPEN: 'Open',
  ASSIGNED: 'Assigned',
  IN_PROGRESS: 'In progress',
  RESOLVED: 'Resolved',
  CLOSED: 'Closed',
};

const userSelect = {
  id: true,
  name: true,
  email: true,
  role: true,
  userId: true,
  tenantId: true,
};

function serialize(ticket, { redactAssignment = false } = {}) {
  const out = {
    ...ticket,
    issueTypeLabel: ISSUE_TYPE_LABELS[ticket.issueType] || ticket.issueType,
    statusLabel: STATUS_LABELS[ticket.status] || ticket.status,
  };
  if (redactAssignment) {
    delete out.assignee;
    delete out.assigneeId;
    delete out.assignedBy;
    delete out.assignedById;
    delete out.assignedAt;
  }
  return out;
}

async function generateTicketNumber() {
  const date = new Date();
  const ymd =
    String(date.getFullYear()) +
    String(date.getMonth() + 1).padStart(2, '0') +
    String(date.getDate()).padStart(2, '0');
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const suffix = Math.floor(1000 + Math.random() * 9000);
    const ticketNumber = `MTK-${ymd}-${suffix}`;
    const existing = await prisma.supportTicket.findUnique({
      where: { ticketNumber },
      select: { id: true },
    });
    if (!existing) return ticketNumber;
  }
  throw new Error('Could not generate ticket number');
}

async function notifySuperAdmins({ io, ticket }) {
  const superAdmins = await prisma.user.findMany({
    where: {
      role: 'SUPER_ADMIN',
      tenantId: tenant.DEFAULT_TENANT_ID,
      status: 'ACTIVE',
    },
    select: { id: true },
  });
  if (!superAdmins.length) return;
  const notifications = require('../notifications/notifications.service');
  await Promise.all(
    superAdmins.map((admin) =>
      notifications.notify({
        userId: admin.id,
        kind: 'SYSTEM',
        title: 'New support ticket',
        body: `${ticket.ticketNumber}: ${ISSUE_TYPE_LABELS[ticket.issueType] || ticket.issueType}`,
        data: { ticketId: ticket.id, ticketNumber: ticket.ticketNumber },
        io,
      }).catch(() => null)
    )
  );
}

async function create(req, { issueType, description }) {
  const reporter = req.user;
  const reporterEmail =
    (reporter.email || '').trim().toLowerCase() ||
    `${reporter.userId || reporter.id}@noreply.local`;

  const ticketNumber = await generateTicketNumber();
  const ticket = await prisma.supportTicket.create({
    data: {
      ticketNumber,
      reporterId: reporter.id,
      reporterEmail,
      reporterName: reporter.name,
      tenantId: reporter.tenantId || tenant.DEFAULT_TENANT_ID,
      issueType,
      description: description.trim(),
    },
    include: {
      reporter: { select: userSelect },
      assignee: { select: userSelect },
      assignedBy: { select: userSelect },
    },
  });

  await notifySuperAdmins({ io: req.app?.get('io'), ticket });

  return serialize(ticket);
}

async function listMine(req) {
  const items = await prisma.supportTicket.findMany({
    where: { reporterId: req.user.id },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      ticketNumber: true,
      issueType: true,
      status: true,
      createdAt: true,
    },
  });
  return items.map((t) => ({
    ...t,
    issueTypeLabel: ISSUE_TYPE_LABELS[t.issueType] || t.issueType,
    statusLabel: STATUS_LABELS[t.status] || t.status,
  }));
}

async function checkStatus(req, { ticketNumber }) {
  const normalizedNumber = ticketNumber.trim().toUpperCase();
  const ticket = await prisma.supportTicket.findUnique({
    where: { ticketNumber: normalizedNumber },
    include: {
      reporter: { select: userSelect },
      assignee: { select: userSelect },
      assignedBy: { select: userSelect },
    },
  });
  if (!ticket) throw NotFound('Issue not found');

  if (ticket.reporterId !== req.user.id && !tenant.isPlatformSuperAdmin(req.user)) {
    throw Forbidden('You can only check your own issues');
  }

  const redactAssignment = !tenant.isPlatformSuperAdmin(req.user);
  return serialize(ticket, { redactAssignment });
}

async function listAdmin(req) {
  if (!tenant.isPlatformSuperAdmin(req.user)) throw Forbidden('Super admin only');
  const items = await prisma.supportTicket.findMany({
    orderBy: { createdAt: 'desc' },
    include: {
      reporter: { select: userSelect },
      assignee: { select: userSelect },
      assignedBy: { select: userSelect },
    },
  });
  return items.map(serialize);
}

async function listAssigned(req) {
  const items = await prisma.supportTicket.findMany({
    where: { assigneeId: req.user.id },
    orderBy: { updatedAt: 'desc' },
    include: {
      reporter: { select: userSelect },
      assignee: { select: userSelect },
      assignedBy: { select: userSelect },
    },
  });
  return items.map(serialize);
}

async function listAssignees(req, { q }) {
  if (!tenant.isPlatformSuperAdmin(req.user)) throw Forbidden('Super admin only');
  const where = {
    tenantId: tenant.DEFAULT_TENANT_ID,
    isClient: false,
    status: 'ACTIVE',
    role: { not: 'SUPER_ADMIN' },
    ...(q
      ? {
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { email: { contains: q, mode: 'insensitive' } },
            { userId: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
  };
  const items = await prisma.user.findMany({
    where,
    orderBy: { name: 'asc' },
    take: 50,
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      userId: true,
      tenantId: true,
      tenant: { select: { id: true, name: true } },
    },
  });
  return items;
}

async function assign(req, id, { assigneeId }) {
  if (!tenant.isPlatformSuperAdmin(req.user)) throw Forbidden('Super admin only');
  const existing = await prisma.supportTicket.findUnique({ where: { id } });
  if (!existing) throw NotFound('Issue not found');

  const assignee = await prisma.user.findUnique({ where: { id: assigneeId } });
  if (!assignee || assignee.isClient || assignee.status !== 'ACTIVE') {
    throw BadRequest('Choose an active employee');
  }
  if (assignee.role === 'SUPER_ADMIN') {
    throw BadRequest('Cannot assign to super admin');
  }
  if ((assignee.tenantId || tenant.DEFAULT_TENANT_ID) !== tenant.DEFAULT_TENANT_ID) {
    throw BadRequest('Support issues can only be assigned to platform team members');
  }

  const ticket = await prisma.supportTicket.update({
    where: { id },
    data: {
      assigneeId,
      assignedById: req.user.id,
      assignedAt: new Date(),
      status: existing.status === 'OPEN' ? 'ASSIGNED' : existing.status,
    },
    include: {
      reporter: { select: userSelect },
      assignee: { select: userSelect },
      assignedBy: { select: userSelect },
    },
  });

  const notifications = require('../notifications/notifications.service');
  await notifications
    .notify({
      userId: assigneeId,
      kind: 'SYSTEM',
      title: 'Support issue assigned',
      body: `${ticket.ticketNumber} — ${ISSUE_TYPE_LABELS[ticket.issueType] || ticket.issueType}`,
      data: { ticketId: ticket.id, ticketNumber: ticket.ticketNumber },
      io: req.app?.get('io'),
    })
    .catch(() => null);

  return serialize(ticket);
}

async function updateStatus(req, id, { status, resolutionNotes }) {
  const existing = await prisma.supportTicket.findUnique({ where: { id } });
  if (!existing) throw NotFound('Issue not found');

  const isSuper = tenant.isPlatformSuperAdmin(req.user);
  const isAssignee = existing.assigneeId === req.user.id;
  if (!isSuper && !isAssignee) throw Forbidden('Not allowed to update this issue');

  const data = { status };
  if (resolutionNotes !== undefined) {
    data.resolutionNotes = resolutionNotes?.trim() || null;
  }
  if (status === 'RESOLVED' || status === 'CLOSED') {
    data.resolvedAt = new Date();
  }

  const ticket = await prisma.supportTicket.update({
    where: { id },
    data,
    include: {
      reporter: { select: userSelect },
      assignee: { select: userSelect },
      assignedBy: { select: userSelect },
    },
  });

  return serialize(ticket);
}

module.exports = {
  ISSUE_TYPE_LABELS,
  STATUS_LABELS,
  create,
  listMine,
  checkStatus,
  listAdmin,
  listAssigned,
  listAssignees,
  assign,
  updateStatus,
};
