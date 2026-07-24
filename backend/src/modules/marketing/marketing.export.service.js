'use strict';

const ExcelJS = require('exceljs');
const prisma = require('../../database/prisma');
const { Forbidden } = require('../../utils/errors');
const { tenantId, isManager } = require('./marketing.helpers');

const MAX_ROWS = 15000;

function formatDt(value) {
  if (!value) return '';
  return new Intl.DateTimeFormat('en-IN', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(new Date(value));
}

function dec(value) {
  if (value == null || value === '') return '';
  return String(value);
}

function jsonList(value) {
  if (value == null) return '';
  if (Array.isArray(value)) return value.join(', ');
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : value;
    return Array.isArray(parsed) ? parsed.join(', ') : String(parsed);
  } catch {
    return String(value);
  }
}

function dateLabel(now = new Date()) {
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return [
    ist.getUTCFullYear(),
    String(ist.getUTCMonth() + 1).padStart(2, '0'),
    String(ist.getUTCDate()).padStart(2, '0'),
  ].join('-');
}

function addSheet(workbook, name, columns, rows) {
  const sheet = workbook.addWorksheet(name.slice(0, 31));
  sheet.columns = columns;
  sheet.getRow(1).font = { bold: true };
  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  for (const row of rows) {
    sheet.addRow(row);
  }
  for (const col of sheet.columns) {
    col.width = Math.min(Math.max((col.header || '').length + 2, 12), 48);
  }
  return rows.length;
}

async function fetchExecutiveIds(tid) {
  return prisma.user.findMany({
    where: { tenantId: tid, role: 'EXECUTIVE' },
    select: { id: true, name: true, userId: true },
    orderBy: { name: 'asc' },
  });
}

async function buildMarketingExport(req, query = {}) {
  if (!isManager(req.user)) throw Forbidden('Manager or admin only');

  const tid = tenantId(req);
  const executives = await fetchExecutiveIds(tid);
  const execIds = executives.map((e) => e.id);
  const executivesOnly = query.all_users !== 'true';
  const execUserFilter = executivesOnly
    ? execIds.length
      ? { userId: { in: execIds } }
      : { userId: '__none__' }
    : {};

  const from = query.from ? new Date(query.from) : null;
  const to = query.to ? new Date(`${query.to}T23:59:59.999Z`) : null;
  const visitDate = {};
  if (from) visitDate.gte = from;
  if (to) visitDate.lte = to;
  const visitDateFilter = Object.keys(visitDate).length ? { checkInAt: visitDate } : {};

  const gpsDate = {};
  if (from) gpsDate.gte = from;
  if (to) gpsDate.lte = to;
  const gpsDateFilter = Object.keys(gpsDate).length ? { loggedAt: gpsDate } : {};

  const orderDate = {};
  if (from) orderDate.gte = from;
  if (to) orderDate.lte = to;
  const orderDateFilter = Object.keys(orderDate).length ? { createdAt: orderDate } : {};

  const [
    outlets,
    visits,
    orders,
    gpsLogs,
    expenses,
    leaves,
    incidents,
    ratings,
    routes,
    dailyPlans,
    products,
    categories,
    brands,
    holidays,
  ] = await Promise.all([
    prisma.marketingOutlet.findMany({
      where: { tenantId: tid },
      take: MAX_ROWS,
      orderBy: { updatedAt: 'desc' },
      include: {
        assignedTo: { select: { name: true, userId: true, role: true } },
        createdBy: { select: { name: true, userId: true } },
      },
    }),
    prisma.fieldVisit.findMany({
      where: { tenantId: tid, ...execUserFilter, ...visitDateFilter },
      take: MAX_ROWS,
      orderBy: { checkInAt: 'desc' },
      include: {
        user: { select: { name: true, userId: true } },
        outlet: { select: { name: true, city: true } },
      },
    }),
    prisma.fieldOrder.findMany({
      where: { tenantId: tid, ...execUserFilter, ...orderDateFilter },
      take: MAX_ROWS,
      orderBy: { createdAt: 'desc' },
      include: {
        user: { select: { name: true, userId: true } },
        outlet: { select: { name: true } },
        items: {
          include: { product: { select: { name: true, sku: true } } },
        },
      },
    }),
    prisma.fieldGpsLog.findMany({
      where: { tenantId: tid, ...execUserFilter, ...gpsDateFilter },
      take: MAX_ROWS,
      orderBy: { loggedAt: 'desc' },
      include: { user: { select: { name: true, userId: true } } },
    }),
    prisma.fieldExpense.findMany({
      where: { tenantId: tid, ...execUserFilter },
      take: MAX_ROWS,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { name: true, userId: true } } },
    }),
    prisma.fieldLeave.findMany({
      where: { tenantId: tid, ...execUserFilter },
      take: MAX_ROWS,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { name: true, userId: true } } },
    }),
    prisma.fieldIncident.findMany({
      where: { tenantId: tid, ...execUserFilter },
      take: MAX_ROWS,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { name: true, userId: true } } },
    }),
    prisma.fieldRating.findMany({
      where: { tenantId: tid, ...execUserFilter },
      take: MAX_ROWS,
      orderBy: { createdAt: 'desc' },
      include: { user: { select: { name: true, userId: true } } },
    }),
    prisma.fieldRoute.findMany({
      where: { tenantId: tid },
      take: MAX_ROWS,
      orderBy: { updatedAt: 'desc' },
      include: { assignedTo: { select: { name: true, userId: true } } },
    }),
    prisma.fieldDailyPlan.findMany({
      where: { tenantId: tid, ...execUserFilter },
      take: MAX_ROWS,
      orderBy: { planDate: 'desc' },
      include: {
        user: { select: { name: true, userId: true } },
        route: { select: { name: true } },
      },
    }),
    prisma.marketingProduct.findMany({
      where: { tenantId: tid },
      take: MAX_ROWS,
      orderBy: { name: 'asc' },
      include: {
        category: { select: { name: true } },
        brand: { select: { name: true } },
      },
    }),
    prisma.marketingCategory.findMany({
      where: { tenantId: tid },
      take: MAX_ROWS,
      orderBy: { name: 'asc' },
    }),
    prisma.marketingBrand.findMany({
      where: { tenantId: tid },
      take: MAX_ROWS,
      orderBy: { name: 'asc' },
    }),
    prisma.fieldHoliday.findMany({
      where: { tenantId: tid },
      take: MAX_ROWS,
      orderBy: { date: 'asc' },
    }),
  ]);

  const orderItems = [];
  for (const order of orders) {
    for (const item of order.items || []) {
      orderItems.push({ order, item });
    }
  }

  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'MyTaskKing';
  workbook.created = new Date();

  const label = dateLabel();
  let rowCount = 0;

  const summary = workbook.addWorksheet('Summary');
  summary.columns = [{ width: 28 }, { width: 52 }];
  summary.getColumn(1).font = { bold: true };
  summary.addRows([
    ['Marketing field export', label],
    ['Organisation', tid],
    ['Exported by', req.user.name || req.user.userId || req.user.id],
    ['Scope', executivesOnly ? 'All executives' : 'All field users'],
    ['Executives in org', executives.length],
    ...(from ? [['From', formatDt(from)]] : []),
    ...(to ? [['To', formatDt(to)]] : []),
    ['Outlets', outlets.length],
    ['Visits', visits.length],
    ['Orders', orders.length],
    ['Order line items', orderItems.length],
    ['GPS logs', gpsLogs.length],
    ['Expenses', expenses.length],
    ['Leaves', leaves.length],
    ['Incidents', incidents.length],
    ['Ratings', ratings.length],
    ['Routes', routes.length],
    ['Daily plans', dailyPlans.length],
    ['Products', products.length],
    ['Categories', categories.length],
    ['Brands', brands.length],
    ['Holidays', holidays.length],
  ]);

  rowCount += addSheet(
    workbook,
    'Outlets',
    [
      { header: 'Name', key: 'name' },
      { header: 'Code', key: 'code' },
      { header: 'Phone', key: 'phone' },
      { header: 'Email', key: 'email' },
      { header: 'Address', key: 'address' },
      { header: 'City', key: 'city' },
      { header: 'State', key: 'state' },
      { header: 'Category', key: 'category' },
      { header: 'Latitude', key: 'lat' },
      { header: 'Longitude', key: 'lng' },
      { header: 'Assigned executive', key: 'assignee' },
      { header: 'Executive ID', key: 'assigneeId' },
      { header: 'Approval', key: 'approval' },
      { header: 'Status', key: 'status' },
      { header: 'Source', key: 'source' },
      { header: 'Created', key: 'created' },
    ],
    outlets.map((o) => ({
      name: o.name,
      code: o.code || '',
      phone: o.phone || '',
      email: o.email || '',
      address: o.address || '',
      city: o.city || '',
      state: o.state || '',
      category: o.category || '',
      lat: dec(o.latitude),
      lng: dec(o.longitude),
      assignee: o.assignedTo?.name || '',
      assigneeId: o.assignedTo?.userId || '',
      approval: o.approvalStatus,
      status: o.status,
      source: o.source || '',
      created: formatDt(o.createdAt),
    }))
  );

  rowCount += addSheet(
    workbook,
    'Visits',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Executive ID', key: 'execId' },
      { header: 'Outlet', key: 'outlet' },
      { header: 'City', key: 'city' },
      { header: 'Check-in (IST)', key: 'in' },
      { header: 'Check-out (IST)', key: 'out' },
      { header: 'Status', key: 'status' },
      { header: 'Check-in lat', key: 'lat' },
      { header: 'Check-in lng', key: 'lng' },
      { header: 'Selfie URL', key: 'selfie' },
      { header: 'Notes', key: 'notes' },
    ],
    visits.map((v) => ({
      exec: v.user?.name || '',
      execId: v.user?.userId || '',
      outlet: v.outlet?.name || '',
      city: v.outlet?.city || '',
      in: formatDt(v.checkInAt),
      out: formatDt(v.checkOutAt),
      status: v.status,
      lat: dec(v.checkInLat),
      lng: dec(v.checkInLng),
      selfie: v.selfieUrl || '',
      notes: v.notes || '',
    }))
  );

  rowCount += addSheet(
    workbook,
    'Orders',
    [
      { header: 'Order ID', key: 'id' },
      { header: 'Executive', key: 'exec' },
      { header: 'Outlet', key: 'outlet' },
      { header: 'Subtotal', key: 'sub' },
      { header: 'Discount', key: 'disc' },
      { header: 'GST', key: 'gst' },
      { header: 'Total', key: 'total' },
      { header: 'Payment', key: 'pay' },
      { header: 'Status', key: 'status' },
      { header: 'Created (IST)', key: 'created' },
      { header: 'Notes', key: 'notes' },
    ],
    orders.map((o) => ({
      id: o.id,
      exec: o.user?.name || '',
      outlet: o.outlet?.name || '',
      sub: dec(o.subtotal),
      disc: dec(o.discount),
      gst: dec(o.gst),
      total: dec(o.total),
      pay: o.paymentMode || '',
      status: o.status,
      created: formatDt(o.createdAt),
      notes: o.notes || '',
    }))
  );

  rowCount += addSheet(
    workbook,
    'Order Items',
    [
      { header: 'Order ID', key: 'orderId' },
      { header: 'Product', key: 'product' },
      { header: 'SKU', key: 'sku' },
      { header: 'Qty', key: 'qty' },
      { header: 'Free qty', key: 'free' },
      { header: 'MRP', key: 'mrp' },
      { header: 'PTR', key: 'ptr' },
      { header: 'Discount %', key: 'disc' },
      { header: 'GST %', key: 'gst' },
      { header: 'Line total', key: 'line' },
    ],
    orderItems.map(({ order, item }) => ({
      orderId: order.id,
      product: item.product?.name || '',
      sku: item.product?.sku || '',
      qty: item.quantity,
      free: item.freeQuantity,
      mrp: dec(item.mrp),
      ptr: dec(item.ptr),
      disc: dec(item.discountPercent),
      gst: dec(item.gstPercent),
      line: dec(item.lineTotal),
    }))
  );

  rowCount += addSheet(
    workbook,
    'GPS Logs',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Executive ID', key: 'execId' },
      { header: 'Logged (IST)', key: 'logged' },
      { header: 'Latitude', key: 'lat' },
      { header: 'Longitude', key: 'lng' },
      { header: 'Accuracy', key: 'acc' },
      { header: 'Speed', key: 'speed' },
      { header: 'Battery %', key: 'battery' },
    ],
    gpsLogs.map((g) => ({
      exec: g.user?.name || '',
      execId: g.user?.userId || '',
      logged: formatDt(g.loggedAt),
      lat: dec(g.latitude),
      lng: dec(g.longitude),
      acc: dec(g.accuracy),
      speed: dec(g.speed),
      battery: g.batteryLevel ?? '',
    }))
  );

  rowCount += addSheet(
    workbook,
    'Expenses',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Type', key: 'type' },
      { header: 'Amount', key: 'amount' },
      { header: 'Date', key: 'date' },
      { header: 'Status', key: 'status' },
      { header: 'Description', key: 'desc' },
      { header: 'Receipt URL', key: 'receipt' },
      { header: 'Submitted (IST)', key: 'created' },
    ],
    expenses.map((e) => ({
      exec: e.user?.name || '',
      type: e.type,
      amount: dec(e.amount),
      date: e.expenseDate,
      status: e.status,
      desc: e.description || '',
      receipt: e.receiptUrl || '',
      created: formatDt(e.createdAt),
    }))
  );

  rowCount += addSheet(
    workbook,
    'Leaves',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Leave type', key: 'type' },
      { header: 'From', key: 'from' },
      { header: 'To', key: 'to' },
      { header: 'Days', key: 'days' },
      { header: 'Status', key: 'status' },
      { header: 'Reason', key: 'reason' },
      { header: 'Applied (IST)', key: 'created' },
    ],
    leaves.map((l) => ({
      exec: l.user?.name || '',
      type: l.leaveType,
      from: l.fromDate,
      to: l.toDate,
      days: l.days,
      status: l.status,
      reason: l.reason || '',
      created: formatDt(l.createdAt),
    }))
  );

  rowCount += addSheet(
    workbook,
    'Incidents',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Type', key: 'type' },
      { header: 'Description', key: 'desc' },
      { header: 'Location', key: 'loc' },
      { header: 'Status', key: 'status' },
      { header: 'Reported (IST)', key: 'created' },
    ],
    incidents.map((i) => ({
      exec: i.user?.name || '',
      type: i.type,
      desc: i.description,
      loc: i.location || '',
      status: i.status,
      created: formatDt(i.createdAt),
    }))
  );

  rowCount += addSheet(
    workbook,
    'Ratings',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Entity type', key: 'etype' },
      { header: 'Entity ID', key: 'eid' },
      { header: 'Score', key: 'score' },
      { header: 'Notes', key: 'notes' },
      { header: 'Rated (IST)', key: 'created' },
    ],
    ratings.map((r) => ({
      exec: r.user?.name || '',
      etype: r.entityType,
      eid: r.entityId,
      score: r.score,
      notes: r.notes || '',
      created: formatDt(r.createdAt),
    }))
  );

  rowCount += addSheet(
    workbook,
    'Routes',
    [
      { header: 'Name', key: 'name' },
      { header: 'Assigned executive', key: 'exec' },
      { header: 'Outlet IDs', key: 'outlets' },
      { header: 'Status', key: 'status' },
      { header: 'Description', key: 'desc' },
      { header: 'Updated (IST)', key: 'updated' },
    ],
    routes.map((r) => ({
      name: r.name,
      exec: r.assignedTo?.name || '',
      outlets: jsonList(r.outletIds),
      status: r.status,
      desc: r.description || '',
      updated: formatDt(r.updatedAt),
    }))
  );

  rowCount += addSheet(
    workbook,
    'Daily Plans',
    [
      { header: 'Executive', key: 'exec' },
      { header: 'Plan date', key: 'date' },
      { header: 'Route', key: 'route' },
      { header: 'Outlet IDs', key: 'outlets' },
      { header: 'Status', key: 'status' },
      { header: 'Notes', key: 'notes' },
    ],
    dailyPlans.map((p) => ({
      exec: p.user?.name || '',
      date: p.planDate,
      route: p.route?.name || '',
      outlets: jsonList(p.outletIds),
      status: p.status,
      notes: p.notes || '',
    }))
  );

  rowCount += addSheet(
    workbook,
    'Products',
    [
      { header: 'Name', key: 'name' },
      { header: 'SKU', key: 'sku' },
      { header: 'Category', key: 'cat' },
      { header: 'Brand', key: 'brand' },
      { header: 'MRP', key: 'mrp' },
      { header: 'PTR', key: 'ptr' },
      { header: 'PTS', key: 'pts' },
      { header: 'GST %', key: 'gst' },
      { header: 'UOM', key: 'uom' },
      { header: 'Pack size', key: 'pack' },
      { header: 'Stock', key: 'stock' },
      { header: 'Available', key: 'avail' },
      { header: 'Status', key: 'status' },
    ],
    products.map((p) => ({
      name: p.name,
      sku: p.sku || '',
      cat: p.category?.name || '',
      brand: p.brand?.name || '',
      mrp: dec(p.mrp),
      ptr: dec(p.ptr),
      pts: dec(p.pts),
      gst: dec(p.gstPercent),
      uom: p.uom || '',
      pack: p.packSize ?? '',
      stock: p.stock,
      avail: p.availability ? 'Yes' : 'No',
      status: p.status,
    }))
  );

  rowCount += addSheet(
    workbook,
    'Categories',
    [{ header: 'Name', key: 'name' }, { header: 'Parent ID', key: 'parent' }],
    categories.map((c) => ({ name: c.name, parent: c.parentId || '' }))
  );

  rowCount += addSheet(
    workbook,
    'Brands',
    [{ header: 'Name', key: 'name' }],
    brands.map((b) => ({ name: b.name }))
  );

  rowCount += addSheet(
    workbook,
    'Holidays',
    [{ header: 'Name', key: 'name' }, { header: 'Date', key: 'date' }],
    holidays.map((h) => ({ name: h.name, date: h.date }))
  );

  rowCount += addSheet(
    workbook,
    'Executives',
    [
      { header: 'Name', key: 'name' },
      { header: 'User ID', key: 'uid' },
      { header: 'Internal ID', key: 'id' },
    ],
    executives.map((e) => ({ name: e.name, uid: e.userId, id: e.id }))
  );

  const buffer = Buffer.from(await workbook.xlsx.writeBuffer());
  const filename = `marketing-field-export-${tid}-${label}.xlsx`;

  return { buffer, filename, rowCount, executives: executives.length };
}

module.exports = { buildMarketingExport };
