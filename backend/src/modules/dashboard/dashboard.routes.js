'use strict';

const { Router } = require('express');
const asyncHandler = require('../../utils/asyncHandler');
const { requireAuth } = require('../../middleware/auth');
const service = require('./dashboard.service');

const router = Router();
router.use(requireAuth);

router.get(
  '/overview',
  asyncHandler(async (req, res) => {
    if (req.user.isClient) return res.json(await service.clientOverview(req.user));
    if (['SUPER_ADMIN', 'ADMIN'].includes(req.user.role)) {
      return res.json(await service.adminOverview(req.user));
    }
    return res.json(await service.employeeOverview(req.user));
  })
);

module.exports = router;
