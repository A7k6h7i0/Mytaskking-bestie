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

/** Platform team assignees may only set these statuses (not Super Admin). */
const ASSIGNEE_ALLOWED_STATUSES = new Set(['IN_PROGRESS', 'RESOLVED', 'CLOSED']);

const userSelect = {
  id: true,
  name: true,
  email: true,
  role: true,
  userId: true,
  tenantId: true,
};

const ticketInclude = {
  reporter: { select: userSelect },
  assignee: { select: userSelect },
  assignedBy: { select: userSelect },
  assignees: {
    include: { user: { select: userSelect } },
    orderBy: { assignedAt: 'asc' },
  },
};

function mapAssignees(ticket) {
  if (ticket.assignees?.length) {
    return ticket.assignees.map((row) => ({
      id: row.user.id,
      name: row.user.name,
      email: row.user.email,
      role: row.user.role,
      userId: row.user.userId,
      assignedAt: row.assignedAt,
    }));
  }
  if (ticket.assignee) {
    return [
      {
        id: ticket.assignee.id,
        name: ticket.assignee.name,
        email: ticket.assignee.email,
        role: ticket.assignee.role,
        userId: ticket.assignee.userId,
        assignedAt: ticket.assignedAt,
      },
    ];
  }
  return [];
}

function serialize(ticket, { redactAssignment = false } = {}) {
  const assignees = mapAssignees(ticket);
  const { assignees: _rows, ...rest } = ticket;
  const out = {
    ...rest,
    issueTypeLabel: ISSUE_TYPE_LABELS[ticket.issueType] || ticket.issueType,
    statusLabel: STATUS_LABELS[ticket.status] || ticket.status,
  };
  if (!redactAssignment) {
    out.assignees = assignees;
    out.assigneeIds = assignees.map((a) => a.id);
  } else {
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
    include: ticketInclude,
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
    include: ticketInclude,
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
    include: ticketInclude,
  });
  return items.map((t) => serialize(t));
}

async function listAssigned(req) {
  if (!tenant.isDefaultTenantSupportAssignee(req.user)) {
    throw Forbidden('Platform team members only');
  }
  const items = await prisma.supportTicket.findMany({
    where: {
      assignees: { some: { userId: req.user.id } },
    },
    orderBy: { updatedAt: 'desc' },
    include: ticketInclude,
  });
  return items.map((t) => serialize(t));
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
    take: q ? 50 : 200,
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

async function validateAssigneeIds(assigneeIds) {
  const ids = [...new Set((assigneeIds || []).filter(Boolean))];
  if (!ids.length) return [];

  const users = await prisma.user.findMany({
    where: { id: { in: ids } },
  });
  if (users.length !== ids.length) throw BadRequest('One or more employees not found');

  for (const assignee of users) {
    if (assignee.isClient || assignee.status !== 'ACTIVE') {
      throw BadRequest('Choose active employees only');
    }
    if (assignee.role === 'SUPER_ADMIN') {
      throw BadRequest('Cannot assign to super admin');
    }
    if ((assignee.tenantId || tenant.DEFAULT_TENANT_ID) !== tenant.DEFAULT_TENANT_ID) {
      throw BadRequest('Support issues can only be assigned to platform team members');
    }
  }
  return ids;
}

async function assign(req, id, { assigneeIds }) {
  if (!tenant.isPlatformSuperAdmin(req.user)) throw Forbidden('Super admin only');
  const existing = await prisma.supportTicket.findUnique({
    where: { id },
    include: { assignees: { select: { userId: true } } },
  });
  if (!existing) throw NotFound('Issue not found');
  if (existing.status === 'CLOSED') {
    throw BadRequest('Cannot change assignees on a closed ticket');
  }

  const ids = await validateAssigneeIds(assigneeIds);
  const previousIds = new Set(existing.assignees.map((row) => row.userId));
  const newlyAdded = ids.filter((userId) => !previousIds.has(userId));

  const ticket = await prisma.$transaction(async (tx) => {
    await tx.supportTicketAssignee.deleteMany({ where: { ticketId: id } });
    if (ids.length) {
      await tx.supportTicketAssignee.createMany({
        data: ids.map((userId) => ({
          ticketId: id,
          userId,
          assignedById: req.user.id,
        })),
      });
    }
    return tx.supportTicket.update({
      where: { id },
      data: {
        assigneeId: ids[0] || null,
        assignedById: ids.length ? req.user.id : null,
        assignedAt: ids.length ? new Date() : null,
        status:
          ids.length && existing.status === 'OPEN'
            ? 'ASSIGNED'
            : !ids.length && existing.status === 'ASSIGNED'
              ? 'OPEN'
              : existing.status,
      },
      include: ticketInclude,
    });
  });

  if (newlyAdded.length) {
    const notifications = require('../notifications/notifications.service');
    await Promise.all(
      newlyAdded.map((userId) =>
        notifications
          .notify({
            userId,
            kind: 'SYSTEM',
            title: 'Support issue assigned',
            body: `${ticket.ticketNumber} — ${ISSUE_TYPE_LABELS[ticket.issueType] || ticket.issueType}`,
            data: { ticketId: ticket.id, ticketNumber: ticket.ticketNumber },
            io: req.app?.get('io'),
          })
          .catch(() => null)
      )
    );
  }

  return serialize(ticket);
}

async function isActiveAssignee(ticketId, userId) {
  const row = await prisma.supportTicketAssignee.findUnique({
    where: { ticketId_userId: { ticketId, userId } },
  });
  return !!row;
}

async function updateStatus(req, id, { status, resolutionNotes }) {
  const existing = await prisma.supportTicket.findUnique({ where: { id } });
  if (!existing) throw NotFound('Issue not found');

  const isSuper = tenant.isPlatformSuperAdmin(req.user);
  const isAssignee =
    tenant.isDefaultTenantSupportAssignee(req.user) &&
    (await isActiveAssignee(id, req.user.id));
  if (!isSuper && !isAssignee) {
    throw Forbidden('Not allowed to update this issue');
  }

  if (!isSuper && isAssignee) {
    if (existing.status === 'CLOSED') {
      throw BadRequest('Closed issues cannot be updated');
    }
    if (!ASSIGNEE_ALLOWED_STATUSES.has(status)) {
      throw BadRequest('Employees can only set status to In progress, Resolved, or Closed');
    }
  }

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
    include: ticketInclude,
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
