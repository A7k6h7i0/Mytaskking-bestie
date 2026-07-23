'use strict';

const { Router } = require('express');
const asyncHandler = require('../../utils/asyncHandler');
const { requireAuth } = require('../../middleware/auth');
const { assertFieldAccess } = require('./marketing.helpers');
const service = require('./marketing.service');
const ops = require('./marketing.ops.service');

const DATA_BASE =
  process.env.BUSINESS_DATA_URL || 'https://data.mytaskking.com';

const router = Router();

router.use(requireAuth);
router.use((req, _res, next) => {
  try {
    assertFieldAccess(req.user);
    next();
  } catch (e) {
    next(e);
  }
});

router.get(
  '/settings',
  asyncHandler(async (req, res) => {
    res.json(await service.getFieldSettingsForClient(req));
  })
);

router.get(
  '/dashboard',
  asyncHandler(async (req, res) => {
    res.json(await service.fieldDashboard(req));
  })
);

router.get(
  '/regions',
  asyncHandler(async (req, res) => res.json(await service.listRegions(req)))
);
router.post(
  '/regions',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createRegion(req, req.body))
  )
);

// ---- outlets ----
router.get(
  '/outlets',
  asyncHandler(async (req, res) => res.json(await service.listOutlets(req, req.query)))
);
router.post(
  '/outlets',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createOutlet(req, req.body))
  )
);
router.get(
  '/outlets/:id',
  asyncHandler(async (req, res) => res.json(await service.getOutlet(req, req.params.id)))
);
router.patch(
  '/outlets/:id',
  asyncHandler(async (req, res) =>
    res.json(await service.updateOutlet(req, req.params.id, req.body))
  )
);
router.delete(
  '/outlets/:id',
  asyncHandler(async (req, res) => {
    await service.deactivateOutlet(req, req.params.id);
    res.status(204).end();
  })
);
router.post(
  '/outlets/:id/approve',
  asyncHandler(async (req, res) =>
    res.json(await service.approveOutlet(req, req.params.id))
  )
);

// ---- visits ----
router.post(
  '/visits/start',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.startVisit(req, req.body))
  )
);
router.post(
  '/visits/:id/end',
  asyncHandler(async (req, res) =>
    res.json(await service.endVisit(req, req.params.id, req.body))
  )
);
router.get(
  '/visits/active',
  asyncHandler(async (req, res) => {
    const visit = await service.getActiveVisit(req);
    res.json({ visit });
  })
);
router.get(
  '/visits/my',
  asyncHandler(async (req, res) => res.json(await service.listMyVisits(req, req.query)))
);
router.get(
  '/visits',
  asyncHandler(async (req, res) => res.json(await service.listVisits(req, req.query)))
);

// ---- GPS ----
router.post(
  '/gps',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.logGps(req, req.body))
  )
);
router.get(
  '/gps',
  asyncHandler(async (req, res) => res.json(await service.listGps(req, req.query)))
);

// ---- products / catalog ----
router.get(
  '/products',
  asyncHandler(async (req, res) => res.json(await service.listProducts(req, req.query)))
);
router.post(
  '/products',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createProduct(req, req.body))
  )
);
router.get(
  '/categories',
  asyncHandler(async (req, res) => res.json(await service.listCategories(req)))
);
router.post(
  '/categories',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createCategory(req, req.body))
  )
);
router.get(
  '/brands',
  asyncHandler(async (req, res) => res.json(await service.listBrands(req)))
);
router.post(
  '/brands',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createBrand(req, req.body))
  )
);
router.get(
  '/territories',
  asyncHandler(async (req, res) => res.json(await service.listTerritories(req)))
);
router.post(
  '/territories',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createTerritory(req, req.body))
  )
);
router.get(
  '/distributors',
  asyncHandler(async (req, res) => res.json(await service.listDistributors(req)))
);
router.post(
  '/distributors',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createDistributor(req, req.body))
  )
);

// ---- orders ----
router.get(
  '/orders',
  asyncHandler(async (req, res) => res.json(await service.listOrders(req, req.query)))
);
router.post(
  '/orders',
  asyncHandler(async (req, res) =>
    res.status(201).json(await service.createOrder(req, req.body))
  )
);

// ---- business directory proxy (data.mytaskking.com) ----
router.get(
  '/businesses/search',
  asyncHandler(async (req, res) => {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(req.query)) {
      if (v != null && String(v).length) params.set(k, String(v));
    }
    const url = `${DATA_BASE}/api/v1/businesses/search?${params.toString()}`;
    const upstream = await fetch(url, {
      headers: { Accept: 'application/json' },
    });
    const text = await upstream.text();
    res.status(upstream.status);
    try {
      res.json(JSON.parse(text));
    } catch {
      res.type('text/plain').send(text);
    }
  })
);

// ---- HR ops: expenses, leaves, incidents, ratings ----
router.get('/expenses', asyncHandler(async (req, res) => res.json(await ops.listExpenses(req, req.query))));
router.post('/expenses', asyncHandler(async (req, res) => res.status(201).json(await ops.createExpense(req, req.body))));
router.post('/expenses/:id/approve', asyncHandler(async (req, res) => res.json(await ops.approveExpense(req, req.params.id))));
router.post('/expenses/:id/reject', asyncHandler(async (req, res) => res.json(await ops.rejectExpense(req, req.params.id, req.body))));

router.get('/leaves', asyncHandler(async (req, res) => res.json(await ops.listLeaves(req, req.query))));
router.post('/leaves', asyncHandler(async (req, res) => res.status(201).json(await ops.createLeave(req, req.body))));
router.post('/leaves/:id/approve', asyncHandler(async (req, res) => res.json(await ops.approveLeave(req, req.params.id))));
router.post('/leaves/:id/reject', asyncHandler(async (req, res) => res.json(await ops.rejectLeave(req, req.params.id, req.body))));
router.get('/holidays', asyncHandler(async (req, res) => res.json(await ops.listHolidays(req))));
router.post('/holidays', asyncHandler(async (req, res) => res.status(201).json(await ops.createHoliday(req, req.body))));

router.get('/incidents', asyncHandler(async (req, res) => res.json(await ops.listIncidents(req, req.query))));
router.post('/incidents', asyncHandler(async (req, res) => res.status(201).json(await ops.createIncident(req, req.body))));
router.post('/incidents/:id/resolve', asyncHandler(async (req, res) => res.json(await ops.resolveIncident(req, req.params.id, req.body))));

router.get('/ratings', asyncHandler(async (req, res) => res.json(await ops.listRatings(req, req.query))));
router.post('/ratings', asyncHandler(async (req, res) => res.status(201).json(await ops.createRating(req, req.body))));

// ---- field routes & daily plans ----
router.get('/routes', asyncHandler(async (req, res) => res.json(await ops.listFieldRoutes(req, req.query))));
router.post('/routes', asyncHandler(async (req, res) => res.status(201).json(await ops.createFieldRoute(req, req.body))));
router.patch('/routes/:id', asyncHandler(async (req, res) => res.json(await ops.updateFieldRoute(req, req.params.id, req.body))));
router.get('/daily-plans', asyncHandler(async (req, res) => res.json(await ops.listDailyPlans(req, req.query))));
router.post('/daily-plans', asyncHandler(async (req, res) => res.status(201).json(await ops.createDailyPlan(req, req.body))));

// ---- offline sync ----
router.post('/sync/pull', asyncHandler(async (req, res) => res.json(await ops.syncPull(req, req.body))));
router.post('/sync/batch', asyncHandler(async (req, res) => res.json(await ops.syncBatch(req, req.body))));
router.get('/sync/status', asyncHandler(async (_req, res) => {
  res.json({ status: 'ok', serverTime: new Date().toISOString() });
}));

module.exports = router;
