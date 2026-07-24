'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const {
  tenantId,
  isManager,
  assertManager,
  assertExecutiveFieldWorker,
  assertNotOwnSubmission,
  executiveOutletWhere,
  parsePage,
  paginate,
} = require('./marketing.helpers');

const userSelect = { id: true, name: true, userId: true };

async function listExpenses(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.status ? { status: query.status } : {}),
    ...(query.type ? { type: query.type } : {}),
    ...(!isManager(req.user) ? { userId: req.user.id } : {}),
    ...(query.user_id && isManager(req.user) ? { userId: query.user_id } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldExpense.count({ where }),
    prisma.fieldExpense.findMany({
      where,
      skip,
      take,
      orderBy: { expenseDate: 'desc' },
      include: { user: { select: userSelect } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createExpense(req, body) {
  if (!body.type || body.amount == null || (!body.expense_date && !body.expenseDate)) {
    throw BadRequest('type, amount, expense_date required');
  }
  return prisma.fieldExpense.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      type: body.type,
      amount: body.amount,
      description: body.description || null,
      receiptUrl: body.receipt_url || body.receiptUrl || null,
      expenseDate: body.expense_date || body.expenseDate,
    },
    include: { user: { select: userSelect } },
  });
}

async function approveExpense(req, id) {
  assertManager(req.user);
  const row = await prisma.fieldExpense.findFirst({ where: { id, tenantId: tenantId(req) } });
  if (!row) throw NotFound('Expense not found');
  assertNotOwnSubmission(req, row);
  return prisma.fieldExpense.update({
    where: { id },
    data: { status: 'approved', approvedById: req.user.id, approvedAt: new Date() },
  });
}

async function rejectExpense(req, id, body) {
  assertManager(req.user);
  const row = await prisma.fieldExpense.findFirst({ where: { id, tenantId: tenantId(req) } });
  if (!row) throw NotFound('Expense not found');
  assertNotOwnSubmission(req, row);
  return prisma.fieldExpense.update({
    where: { id },
    data: { status: 'rejected', rejectionReason: body.reason || null },
  });
}

async function listLeaves(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.status ? { status: query.status } : {}),
    ...(!isManager(req.user) ? { userId: req.user.id } : {}),
    ...(query.user_id && isManager(req.user) ? { userId: query.user_id } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldLeave.count({ where }),
    prisma.fieldLeave.findMany({
      where,
      skip,
      take,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: userSelect } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createLeave(req, body) {
  if (!body.leave_type && !body.leaveType) throw BadRequest('leave_type required');
  if (!body.from_date && !body.fromDate) throw BadRequest('from_date required');
  if (!body.to_date && !body.toDate) throw BadRequest('to_date required');
  return prisma.fieldLeave.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      leaveType: body.leave_type || body.leaveType,
      fromDate: body.from_date || body.fromDate,
      toDate: body.to_date || body.toDate,
      days: Number(body.days) || 1,
      reason: body.reason || null,
    },
    include: { user: { select: userSelect } },
  });
}

async function approveLeave(req, id) {
  assertManager(req.user);
  const row = await prisma.fieldLeave.findFirst({ where: { id, tenantId: tenantId(req) } });
  if (!row) throw NotFound('Leave not found');
  assertNotOwnSubmission(req, row);
  return prisma.fieldLeave.update({
    where: { id },
    data: { status: 'approved', approvedById: req.user.id, approvedAt: new Date() },
  });
}

async function rejectLeave(req, id, body) {
  assertManager(req.user);
  const row = await prisma.fieldLeave.findFirst({ where: { id, tenantId: tenantId(req) } });
  if (!row) throw NotFound('Leave not found');
  assertNotOwnSubmission(req, row);
  return prisma.fieldLeave.update({
    where: { id },
    data: { status: 'rejected', rejectionReason: body.reason || null },
  });
}

async function listHolidays(req) {
  return prisma.fieldHoliday.findMany({
    where: { tenantId: tenantId(req) },
    orderBy: { date: 'asc' },
  });
}

async function createHoliday(req, body) {
  assertManager(req.user);
  if (!body.name || !body.date) throw BadRequest('name and date required');
  return prisma.fieldHoliday.create({
    data: { tenantId: tenantId(req), name: body.name, date: body.date },
  });
}

async function listIncidents(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.status ? { status: query.status } : {}),
    ...(!isManager(req.user) ? { userId: req.user.id } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldIncident.count({ where }),
    prisma.fieldIncident.findMany({
      where,
      skip,
      take,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: userSelect } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createIncident(req, body) {
  if (!body.type || !body.description) throw BadRequest('type and description required');
  return prisma.fieldIncident.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      type: body.type,
      description: body.description,
      location: body.location || null,
      mediaUrls: body.media_urls ? JSON.stringify(body.media_urls) : body.mediaUrls || null,
      offlineId: body.offline_id || body.offlineId || null,
    },
    include: { user: { select: userSelect } },
  });
}

async function resolveIncident(req, id, body) {
  assertManager(req.user);
  const row = await prisma.fieldIncident.findFirst({ where: { id, tenantId: tenantId(req) } });
  if (!row) throw NotFound('Incident not found');
  assertNotOwnSubmission(req, row);
  return prisma.fieldIncident.update({
    where: { id },
    data: {
      status: 'resolved',
      resolvedById: req.user.id,
      resolvedAt: new Date(),
      resolutionNotes: body.notes || body.resolution_notes || null,
    },
  });
}

async function listRatings(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.entity_type ? { entityType: query.entity_type } : {}),
    ...(query.entity_id ? { entityId: query.entity_id } : {}),
    ...(!isManager(req.user) ? { userId: req.user.id } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldRating.count({ where }),
    prisma.fieldRating.findMany({
      where,
      skip,
      take,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: userSelect } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createRating(req, body) {
  if (!body.entity_type && !body.entityType) throw BadRequest('entity_type required');
  if (!body.entity_id && !body.entityId) throw BadRequest('entity_id required');
  if (body.score == null) throw BadRequest('score required');
  return prisma.fieldRating.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      entityType: body.entity_type || body.entityType,
      entityId: body.entity_id || body.entityId,
      score: Number(body.score),
      notes: body.notes || null,
    },
  });
}

async function listFieldRoutes(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.assigned_to ? { assignedToId: query.assigned_to } : {}),
    ...(!isManager(req.user) ? { assignedToId: req.user.id } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldRoute.count({ where }),
    prisma.fieldRoute.findMany({
      where,
      skip,
      take,
      orderBy: { updatedAt: 'desc' },
      include: { assignedTo: { select: userSelect } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createFieldRoute(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.fieldRoute.create({
    data: {
      tenantId: tenantId(req),
      name: body.name.trim(),
      description: body.description || null,
      assignedToId: body.assigned_to || body.assignedToId || null,
      outletIds: body.outlet_ids || body.outletIds || [],
      createdById: req.user.id,
    },
    include: { assignedTo: { select: userSelect } },
  });
}

async function updateFieldRoute(req, id, body) {
  assertManager(req.user);
  const prev = await prisma.fieldRoute.findFirst({ where: { id, tenantId: tenantId(req) } });
  if (!prev) throw NotFound('Route not found');
  const data = {};
  if (body.name != null) data.name = body.name;
  if (body.description != null) data.description = body.description;
  if (body.assigned_to != null || body.assignedToId != null) {
    data.assignedToId = body.assigned_to || body.assignedToId;
  }
  if (body.outlet_ids != null || body.outletIds != null) {
    data.outletIds = body.outlet_ids || body.outletIds;
  }
  if (body.status != null) data.status = body.status;
  return prisma.fieldRoute.update({ where: { id }, data });
}

async function listDailyPlans(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.date || query.plan_date ? { planDate: query.date || query.plan_date } : {}),
    ...(query.user_id && isManager(req.user)
      ? { userId: query.user_id }
      : !isManager(req.user)
        ? { userId: req.user.id }
        : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldDailyPlan.count({ where }),
    prisma.fieldDailyPlan.findMany({
      where,
      skip,
      take,
      orderBy: { planDate: 'desc' },
      include: {
        user: { select: userSelect },
        route: { select: { id: true, name: true } },
      },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createDailyPlan(req, body) {
  if (!body.plan_date && !body.planDate) throw BadRequest('plan_date required');
  const targetUser =
    isManager(req.user) && (body.user_id || body.userId)
      ? body.user_id || body.userId
      : req.user.id;
  return prisma.fieldDailyPlan.create({
    data: {
      tenantId: tenantId(req),
      userId: targetUser,
      planDate: body.plan_date || body.planDate,
      routeId: body.route_id || body.routeId || null,
      outletIds: body.outlet_ids || body.outletIds || [],
      notes: body.notes || null,
      createdById: req.user.id,
    },
    include: {
      user: { select: userSelect },
      route: { select: { id: true, name: true } },
    },
  });
}

async function syncPull(req, body = {}) {
  const tid = tenantId(req);
  const since = body.last_synced_at || body.lastSyncedAt
    ? new Date(body.last_synced_at || body.lastSyncedAt)
    : new Date(0);

  const [outlets, products, distributors, routes] = await Promise.all([
    prisma.marketingOutlet.findMany({
      where: {
        tenantId: tid,
        updatedAt: { gte: since },
        ...(isManager(req.user) ? {} : executiveOutletWhere(req.user)),
      },
      take: 500,
    }),
    prisma.marketingProduct.findMany({
      where: { tenantId: tid, updatedAt: { gte: since } },
      take: 500,
    }),
    prisma.marketingDistributor.findMany({
      where: { tenantId: tid, updatedAt: { gte: since } },
      take: 200,
    }),
    prisma.fieldRoute.findMany({
      where: {
        tenantId: tid,
        updatedAt: { gte: since },
        ...(!isManager(req.user) ? { assignedToId: req.user.id } : {}),
      },
      take: 100,
    }),
  ]);

  return { syncedAt: new Date().toISOString(), outlets, products, distributors, routes };
}

async function syncBatch(req, body = {}) {
  assertExecutiveFieldWorker(req.user);
  const tid = tenantId(req);
  const userId = req.user.id;
  const visits = Array.isArray(body.visits) ? body.visits : [];
  const gps = Array.isArray(body.gps) ? body.gps : [];
  const incidents = Array.isArray(body.incidents) ? body.incidents : [];

  let processedVisits = 0;
  let processedGps = 0;
  let processedIncidents = 0;

  await prisma.$transaction(async (tx) => {
    for (const v of visits) {
      const offlineId = v.offline_id || v.offlineId;
      if (offlineId) {
        const dup = await tx.fieldVisit.findFirst({
          where: { tenantId: tid, userId, notes: { contains: offlineId } },
        });
        if (dup) continue;
      }
      await tx.fieldVisit.create({
        data: {
          tenantId: tid,
          userId,
          outletId: v.outlet_id || v.outletId,
          checkInAt: v.check_in_at ? new Date(v.check_in_at) : new Date(),
          checkOutAt: v.check_out_at ? new Date(v.check_out_at) : null,
          checkInLat: v.latitude ?? v.check_in_lat ?? null,
          checkInLng: v.longitude ?? v.check_in_lng ?? null,
          selfieUrl: v.selfie_url || v.selfieUrl || 'auto-detected',
          status: v.status || 'completed',
          notes: offlineId ? `offline:${offlineId}` : v.notes || null,
        },
      });
      processedVisits += 1;
    }

    for (const g of gps) {
      const offlineId = g.offline_id || g.offlineId;
      if (offlineId) {
        const dup = await tx.fieldGpsLog.findFirst({
          where: { tenantId: tid, userId, offlineId },
        });
        if (dup) continue;
      }
      await tx.fieldGpsLog.create({
        data: {
          tenantId: tid,
          userId,
          latitude: g.latitude,
          longitude: g.longitude,
          accuracy: g.accuracy ?? null,
          offlineId: offlineId || null,
          loggedAt: g.logged_at ? new Date(g.logged_at) : new Date(),
        },
      });
      processedGps += 1;
    }

    for (const i of incidents) {
      const offlineId = i.offline_id || i.offlineId;
      if (offlineId) {
        const dup = await tx.fieldIncident.findFirst({
          where: { tenantId: tid, offlineId },
        });
        if (dup) continue;
      }
      await tx.fieldIncident.create({
        data: {
          tenantId: tid,
          userId,
          type: i.type,
          description: i.description,
          location: i.location || null,
          mediaUrls: i.media_urls ? JSON.stringify(i.media_urls) : null,
          offlineId: offlineId || null,
        },
      });
      processedIncidents += 1;
    }
  });

  return { processedVisits, processedGps, processedIncidents };
}

module.exports = {
  listExpenses,
  createExpense,
  approveExpense,
  rejectExpense,
  listLeaves,
  createLeave,
  approveLeave,
  rejectLeave,
  listHolidays,
  createHoliday,
  listIncidents,
  createIncident,
  resolveIncident,
  listRatings,
  createRating,
  listFieldRoutes,
  createFieldRoute,
  updateFieldRoute,
  listDailyPlans,
  createDailyPlan,
  syncPull,
  syncBatch,
};
