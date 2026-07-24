'use strict';

const prisma = require('../../database/prisma');
const { NotFound, Forbidden, BadRequest } = require('../../utils/errors');
const {
  tenantId,
  isManager,
  isExecutive,
  assertManager,
  assertExecutiveFieldWorker,
  assertNotOwnSubmission,
  assertExecutiveOutletRead,
  assertExecutiveOutletTransact,
  parsePage,
  paginate,
} = require('./marketing.helpers');
const { getFieldSettings } = require('./marketing.settings');

// ---- outlets ----

async function listOutlets(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.include_bad_parties === 'true' ? {} : { partyStatus: 'active' }),
    ...(query.status ? { status: query.status } : {}),
    ...(query.territory_id ? { territoryId: query.territory_id } : {}),
    ...(query.assigned_to ? { assignedToId: query.assigned_to } : {}),
    ...(query.search
      ? { name: { contains: query.search, mode: 'insensitive' } }
      : {}),
    ...(query.approval_status
      ? { approvalStatus: query.approval_status }
      : {}),
    ...(!isManager(req.user) && !query.assigned_to && !query.approval_status
        ? {
            OR: [
              { createdById: req.user.id },
              {
                AND: [
                  { assignedToId: req.user.id },
                  { approvalStatus: 'approved' },
                ],
              },
            ],
          }
        : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.marketingOutlet.count({ where }),
    prisma.marketingOutlet.findMany({
      where,
      skip,
      take,
      orderBy: { updatedAt: 'desc' },
      include: {
        assignedTo: { select: { id: true, name: true, userId: true } },
      },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createOutlet(req, body) {
  if (!body.name?.trim()) throw BadRequest('name required');
  const settings = await getFieldSettings(req);
  const needsApproval =
    settings.outletCreationApprovalRequired && !isManager(req.user);
  const assigneeId = body.assigned_to || body.assignedToId || null;
  if (isManager(req.user) && !isExecutive(req.user) && !assigneeId) {
    throw BadRequest('Assign a field executive when creating an outlet');
  }
  return prisma.marketingOutlet.create({
    data: {
      tenantId: tenantId(req),
      name: body.name.trim(),
      code: body.code || null,
      ownerName: body.owner_name || body.ownerName || null,
      phone: body.phone || null,
      email: body.email || null,
      address: body.address || null,
      city: body.city || null,
      state: body.state || null,
      pincode: body.pincode || null,
      category: body.category || null,
      source: body.source || 'manual',
      latitude: body.latitude ?? null,
      longitude: body.longitude ?? null,
      territoryId: body.territory_id || body.territoryId || null,
      regionId: body.region_id || body.regionId || null,
      distributorId: body.distributor_id || body.distributorId || null,
      assignedToId: assigneeId || req.user.id,
      grade: body.grade || null,
      approvalStatus: needsApproval ? 'pending' : 'approved',
      createdById: req.user.id,
    },
  });
}

async function getOutlet(req, id) {
  const row = await prisma.marketingOutlet.findFirst({
    where: { id, tenantId: tenantId(req) },
    include: {
      assignedTo: { select: { id: true, name: true, userId: true } },
    },
  });
  if (!row) throw NotFound('Outlet not found');
  assertExecutiveOutletRead(req.user, row);
  return row;
}

async function updateOutlet(req, id, body) {
  const prev = await getOutlet(req, id);
  if (
    prev.assignedToId !== req.user.id &&
    !isManager(req.user)
  ) {
    throw Forbidden('Not authorized');
  }
  const data = {};
  const map = {
    name: 'name',
    owner_name: 'ownerName',
    ownerName: 'ownerName',
    phone: 'phone',
    email: 'email',
    address: 'address',
    city: 'city',
    state: 'state',
    pincode: 'pincode',
    latitude: 'latitude',
    longitude: 'longitude',
    territory_id: 'territoryId',
    territoryId: 'territoryId',
    region_id: 'regionId',
    regionId: 'regionId',
    distributor_id: 'distributorId',
    distributorId: 'distributorId',
    assigned_to: 'assignedToId',
    assignedToId: 'assignedToId',
    grade: 'grade',
    status: 'status',
    category: 'category',
    next_visit_date: 'nextVisitDate',
    nextVisitDate: 'nextVisitDate',
    party_status: 'partyStatus',
    partyStatus: 'partyStatus',
    photo_urls: 'photoUrls',
    photoUrls: 'photoUrls',
  };
  for (const [k, field] of Object.entries(map)) {
    if (body[k] !== undefined) data[field] = body[k];
  }
  return prisma.marketingOutlet.update({ where: { id }, data });
}

async function deactivateOutlet(req, id) {
  const prev = await getOutlet(req, id);
  if (
    prev.assignedToId !== req.user.id &&
    prev.createdById !== req.user.id &&
    !isManager(req.user)
  ) {
    throw Forbidden('Not authorized');
  }
  return prisma.marketingOutlet.update({
    where: { id },
    data: { status: 'inactive' },
  });
}

async function approveOutlet(req, id) {
  assertManager(req.user);
  const row = await getOutlet(req, id);
  assertNotOwnSubmission(req, row, 'createdById');
  return prisma.marketingOutlet.update({
    where: { id },
    data: { approvalStatus: 'approved' },
  });
}

// ---- visits ----

async function startVisit(req, body) {
  assertExecutiveFieldWorker(req.user);
  if (!body.outlet_id && !body.outletId) throw BadRequest('outlet_id required');
  const settings = await getFieldSettings(req);
  const selfieProvided = !!(body.selfie_url || body.selfieUrl);
  if (settings.visitSelfieRequired && !selfieProvided) {
    throw BadRequest('Selfie is required to start a visit');
  }
  const outletId = body.outlet_id || body.outletId;
  const outlet = await getOutlet(req, outletId);
  assertExecutiveOutletTransact(req.user, outlet);

  const active = await prisma.fieldVisit.findFirst({
    where: {
      tenantId: tenantId(req),
      userId: req.user.id,
      status: 'in_progress',
    },
    include: { outlet: { select: { id: true, name: true } } },
  });
  if (active) {
    throw BadRequest(
      active.outletId === outletId
        ? 'Visit already in progress at this outlet'
        : `Finish your visit at ${active.outlet?.name || 'another outlet'} before starting a new one`
    );
  }

  return prisma.fieldVisit.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      outletId,
      planId: body.plan_id || body.planId || null,
      checkInAt: new Date(),
      checkInLat: body.latitude ?? body.check_in_lat ?? null,
      checkInLng: body.longitude ?? body.check_in_lng ?? null,
      selfieUrl: body.selfie_url || body.selfieUrl || 'auto-detected',
      status: 'in_progress',
    },
  });
}

async function endVisit(req, id, body) {
  const prev = await prisma.fieldVisit.findFirst({
    where: { id, tenantId: tenantId(req), userId: req.user.id },
  });
  if (!prev) throw NotFound('Visit not found');
  const updated = await prisma.fieldVisit.update({
    where: { id },
    data: {
      checkOutAt: new Date(),
      notes: body.notes || null,
      status: 'completed',
    },
  });
  if (body.next_visit_date || body.nextVisitDate) {
    await prisma.marketingOutlet.update({
      where: { id: prev.outletId },
      data: { nextVisitDate: new Date(body.next_visit_date || body.nextVisitDate) },
    });
  }
  return updated;
}

async function listMyVisits(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    userId: req.user.id,
    ...(query.status ? { status: query.status } : {}),
    ...(query.from ? { checkInAt: { gte: new Date(query.from) } } : {}),
    ...(query.to ? { checkInAt: { lte: new Date(query.to) } } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldVisit.count({ where }),
    prisma.fieldVisit.findMany({
      where,
      skip,
      take,
      orderBy: { checkInAt: 'desc' },
      include: { outlet: { select: { id: true, name: true } } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function listVisits(req, query = {}) {
  assertManager(req.user);
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.user_id ? { userId: query.user_id } : {}),
    ...(query.outlet_id ? { outletId: query.outlet_id } : {}),
    ...(query.status ? { status: query.status } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldVisit.count({ where }),
    prisma.fieldVisit.findMany({
      where,
      skip,
      take,
      orderBy: { checkInAt: 'desc' },
      include: {
        user: { select: { id: true, name: true, userId: true } },
        outlet: { select: { id: true, name: true } },
      },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function listRegions(req) {
  return prisma.marketingRegion.findMany({
    where: { tenantId: tenantId(req) },
    orderBy: { name: 'asc' },
    include: { territories: { select: { id: true, name: true } } },
  });
}

async function createRegion(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingRegion.create({
    data: {
      tenantId: tenantId(req),
      name: body.name.trim(),
      code: body.code || null,
    },
  });
}

async function getFieldSettingsForClient(req) {
  return getFieldSettings(req);
}

async function getActiveVisit(req) {
  return prisma.fieldVisit.findFirst({
    where: {
      tenantId: tenantId(req),
      userId: req.user.id,
      status: 'in_progress',
    },
    include: { outlet: { select: { id: true, name: true, address: true, city: true } } },
  });
}

async function logGps(req, body) {
  assertExecutiveFieldWorker(req.user);
  if (body.latitude == null || body.longitude == null) {
    throw BadRequest('latitude and longitude required');
  }
  return prisma.fieldGpsLog.create({
    data: {
      tenantId: tenantId(req),
      userId: req.user.id,
      latitude: body.latitude,
      longitude: body.longitude,
      accuracy: body.accuracy ?? null,
      speed: body.speed ?? null,
      batteryLevel: body.battery_level ?? body.batteryLevel ?? null,
      offlineId: body.offline_id || body.offlineId || null,
      loggedAt: body.logged_at ? new Date(body.logged_at) : new Date(),
    },
  });
}

async function listGps(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(query.user_id && isManager(req.user)
      ? { userId: query.user_id }
      : !isManager(req.user)
        ? { userId: req.user.id }
        : {}),
    ...(query.from ? { loggedAt: { gte: new Date(query.from) } } : {}),
    ...(query.to ? { loggedAt: { lte: new Date(query.to) } } : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldGpsLog.count({ where }),
    prisma.fieldGpsLog.findMany({
      where,
      skip,
      take,
      orderBy: { loggedAt: 'desc' },
      include: { user: { select: { id: true, name: true, userId: true } } },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

// ---- products ----

async function listProducts(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    status: query.status || 'active',
    ...(query.search
      ? { name: { contains: query.search, mode: 'insensitive' } }
      : {}),
  };
  const [total, items] = await prisma.$transaction([
    prisma.marketingProduct.count({ where }),
    prisma.marketingProduct.findMany({
      where,
      skip,
      take,
      orderBy: { name: 'asc' },
      include: { category: true, brand: true },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function createProduct(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingProduct.create({
    data: {
      tenantId: tenantId(req),
      sku: body.sku || null,
      name: body.name.trim(),
      categoryId: body.category_id || body.categoryId || null,
      brandId: body.brand_id || body.brandId || null,
      mrp: body.mrp ?? null,
      ptr: body.ptr ?? null,
      pts: body.pts ?? null,
      gstPercent: body.gst_percent ?? body.gstPercent ?? null,
      uom: body.uom || null,
      packSize: body.pack_size ?? body.packSize ?? null,
      stock: body.stock ?? 0,
      availability: body.availability !== false,
    },
  });
}

async function getProduct(req, id) {
  const row = await prisma.marketingProduct.findFirst({
    where: { id, tenantId: tenantId(req) },
  });
  if (!row) throw NotFound('Product not found');
  return row;
}

async function updateProduct(req, id, body) {
  assertManager(req.user);
  await getProduct(req, id);
  const data = {};
  if (body.name !== undefined) {
    if (!String(body.name).trim()) throw BadRequest('name required');
    data.name = body.name.trim();
  }
  if (body.sku !== undefined) data.sku = body.sku || null;
  if (body.category_id !== undefined || body.categoryId !== undefined) {
    data.categoryId = body.category_id ?? body.categoryId ?? null;
  }
  if (body.brand_id !== undefined || body.brandId !== undefined) {
    data.brandId = body.brand_id ?? body.brandId ?? null;
  }
  if (body.mrp !== undefined) data.mrp = body.mrp;
  if (body.ptr !== undefined) data.ptr = body.ptr;
  if (body.pts !== undefined) data.pts = body.pts;
  if (body.gst_percent !== undefined || body.gstPercent !== undefined) {
    data.gstPercent = body.gst_percent ?? body.gstPercent;
  }
  if (body.uom !== undefined) data.uom = body.uom || null;
  if (body.pack_size !== undefined || body.packSize !== undefined) {
    data.packSize = body.pack_size ?? body.packSize;
  }
  if (body.stock !== undefined) data.stock = body.stock;
  if (body.availability !== undefined) data.availability = body.availability !== false;
  if (body.status !== undefined) data.status = body.status;
  return prisma.marketingProduct.update({
    where: { id },
    data,
    include: { category: true, brand: true },
  });
}

async function deleteProduct(req, id) {
  assertManager(req.user);
  await getProduct(req, id);
  return prisma.marketingProduct.update({
    where: { id },
    data: { status: 'inactive' },
  });
}

async function listCategories(req) {
  return prisma.marketingCategory.findMany({
    where: { tenantId: tenantId(req) },
    orderBy: { name: 'asc' },
  });
}

async function createCategory(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingCategory.create({
    data: {
      tenantId: tenantId(req),
      name: body.name.trim(),
      parentId: body.parent_id || body.parentId || null,
    },
  });
}

async function getCategory(req, id) {
  const row = await prisma.marketingCategory.findFirst({
    where: { id, tenantId: tenantId(req) },
  });
  if (!row) throw NotFound('Category not found');
  return row;
}

async function updateCategory(req, id, body) {
  assertManager(req.user);
  await getCategory(req, id);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingCategory.update({
    where: { id },
    data: {
      name: body.name.trim(),
      ...(body.parent_id !== undefined || body.parentId !== undefined
        ? { parentId: body.parent_id ?? body.parentId ?? null }
        : {}),
    },
  });
}

async function deleteCategory(req, id) {
  assertManager(req.user);
  const tid = tenantId(req);
  await getCategory(req, id);
  await prisma.marketingProduct.updateMany({
    where: { tenantId: tid, categoryId: id },
    data: { categoryId: null },
  });
  await prisma.marketingCategory.delete({ where: { id } });
}

async function listBrands(req) {
  return prisma.marketingBrand.findMany({
    where: { tenantId: tenantId(req) },
    orderBy: { name: 'asc' },
  });
}

async function createBrand(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingBrand.create({
    data: { tenantId: tenantId(req), name: body.name.trim() },
  });
}

async function getBrand(req, id) {
  const row = await prisma.marketingBrand.findFirst({
    where: { id, tenantId: tenantId(req) },
  });
  if (!row) throw NotFound('Brand not found');
  return row;
}

async function updateBrand(req, id, body) {
  assertManager(req.user);
  await getBrand(req, id);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingBrand.update({
    where: { id },
    data: { name: body.name.trim() },
  });
}

async function deleteBrand(req, id) {
  assertManager(req.user);
  const tid = tenantId(req);
  await getBrand(req, id);
  await prisma.marketingProduct.updateMany({
    where: { tenantId: tid, brandId: id },
    data: { brandId: null },
  });
  await prisma.marketingBrand.delete({ where: { id } });
}

// ---- territories / distributors ----

async function listTerritories(req) {
  return prisma.marketingTerritory.findMany({
    where: { tenantId: tenantId(req) },
    orderBy: { name: 'asc' },
    include: { region: true },
  });
}

async function createTerritory(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingTerritory.create({
    data: {
      tenantId: tenantId(req),
      name: body.name.trim(),
      regionId: body.region_id || body.regionId || null,
      description: body.description || null,
    },
  });
}

async function listDistributors(req) {
  return prisma.marketingDistributor.findMany({
    where: { tenantId: tenantId(req), status: 'active' },
    orderBy: { name: 'asc' },
  });
}

async function createDistributor(req, body) {
  assertManager(req.user);
  if (!body.name?.trim()) throw BadRequest('name required');
  return prisma.marketingDistributor.create({
    data: {
      tenantId: tenantId(req),
      name: body.name.trim(),
      phone: body.phone || null,
      email: body.email || null,
      address: body.address || null,
    },
  });
}

// ---- orders ----

async function createOrder(req, body) {
  assertExecutiveFieldWorker(req.user);
  if (!body.outlet_id && !body.outletId) throw BadRequest('outlet_id required');
  const outletId = body.outlet_id || body.outletId;
  const outlet = await getOutlet(req, outletId);
  assertExecutiveOutletTransact(req.user, outlet);
  const items = Array.isArray(body.items) ? body.items : [];
  let subtotal = 0;
  const lineRows = [];
  for (const item of items) {
    const qty = Number(item.quantity) || 0;
    if (!item.product_id && !item.productId) continue;
    const ptr = Number(item.ptr) || 0;
    const lineTotal = ptr * qty;
    subtotal += lineTotal;
    lineRows.push({
      tenantId: tenantId(req),
      productId: item.product_id || item.productId,
      quantity: qty,
      freeQuantity: Number(item.free_quantity) || 0,
      mrp: item.mrp ?? null,
      ptr: item.ptr ?? null,
      discountPercent: item.discount_percent ?? 0,
      gstPercent: item.gst_percent ?? 0,
      lineTotal,
    });
  }
  const discount = Number(body.discount) || 0;
  const gst = Number(body.gst) || 0;
  const total = subtotal - discount + gst;
  return prisma.fieldOrder.create({
    data: {
      tenantId: tenantId(req),
      outletId,
      userId: req.user.id,
      visitId: body.visit_id || body.visitId || null,
      distributorId: body.distributor_id || body.distributorId || null,
      subtotal,
      discount,
      gst,
      total,
      paymentMode: body.payment_mode || body.paymentMode || null,
      creditDays: body.credit_days ?? body.creditDays ?? null,
      notes: body.notes || null,
      status: body.status || 'submitted',
      items: { create: lineRows },
    },
    include: { items: { include: { product: true } }, outlet: true },
  });
}

async function listOrders(req, query = {}) {
  const tid = tenantId(req);
  const { page, pageSize, skip, take } = parsePage(query);
  const where = {
    tenantId: tid,
    ...(isManager(req.user) && query.user_id
      ? { userId: query.user_id }
      : isManager(req.user)
        ? {}
        : { userId: req.user.id }),
  };
  const [total, items] = await prisma.$transaction([
    prisma.fieldOrder.count({ where }),
    prisma.fieldOrder.findMany({
      where,
      skip,
      take,
      orderBy: { createdAt: 'desc' },
      include: {
        outlet: { select: { id: true, name: true } },
        user: { select: { id: true, name: true } },
        items: true,
      },
    }),
  ]);
  return paginate(items, total, page, pageSize);
}

async function getOrder(req, id) {
  const row = await prisma.fieldOrder.findFirst({
    where: { id, tenantId: tenantId(req) },
    include: {
      outlet: {
        select: {
          id: true,
          name: true,
          address: true,
          city: true,
          state: true,
          phone: true,
        },
      },
      user: { select: { id: true, name: true, userId: true } },
      items: {
        include: {
          product: { select: { id: true, name: true, sku: true, uom: true } },
        },
      },
      visit: {
        select: { id: true, checkInAt: true, checkOutAt: true, status: true },
      },
    },
  });
  if (!row) throw NotFound('Order not found');
  if (!isManager(req.user) && row.userId !== req.user.id) {
    throw Forbidden('Not your order');
  }
  return row;
}

// ---- dashboard stats ----

async function fieldDashboard(req) {
  const tid = tenantId(req);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const userFilter = isManager(req.user) ? {} : { userId: req.user.id };
  const [outlets, visitsToday, openVisits, ordersToday] = await Promise.all([
    prisma.marketingOutlet.count({
      where: {
        tenantId: tid,
        status: 'active',
        ...(isManager(req.user) ? {} : { assignedToId: req.user.id }),
      },
    }),
    prisma.fieldVisit.count({
      where: { tenantId: tid, ...userFilter, checkInAt: { gte: today } },
    }),
    prisma.fieldVisit.count({
      where: { tenantId: tid, ...userFilter, status: 'in_progress' },
    }),
    prisma.fieldOrder.count({
      where: { tenantId: tid, ...userFilter, createdAt: { gte: today } },
    }),
  ]);
  return { outlets, visitsToday, openVisits, ordersToday };
}

module.exports = {
  listOutlets,
  createOutlet,
  getOutlet,
  updateOutlet,
  deactivateOutlet,
  approveOutlet,
  startVisit,
  endVisit,
  listMyVisits,
  listVisits,
  getActiveVisit,
  logGps,
  listGps,
  listProducts,
  createProduct,
  updateProduct,
  deleteProduct,
  listCategories,
  createCategory,
  updateCategory,
  deleteCategory,
  listBrands,
  createBrand,
  updateBrand,
  deleteBrand,
  listTerritories,
  createTerritory,
  listDistributors,
  createDistributor,
  createOrder,
  listOrders,
  getOrder,
  fieldDashboard,
  listRegions,
  createRegion,
  getFieldSettingsForClient,
};
