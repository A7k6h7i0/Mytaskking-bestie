'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const { Forbidden, NotFound } = require('../../utils/errors');

function requireSalesHead(req, _res, next) {
  if (!tenant.isSalesHead(req.user)) return next(Forbidden('Sales head only'));
  next();
}

function requireSuperAdmin(req, _res, next) {
  if (!tenant.isPlatformSuperAdmin(req.user)) return next(Forbidden('Super admin only'));
  next();
}

const router = Router();

router.use(requireAuth);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const isSuper = tenant.isPlatformSuperAdmin(req.user);
    const isSales = tenant.isSalesHead(req.user);
    if (!isSuper && !isSales) throw Forbidden();
    const items = await prisma.adminNote.findMany({
      where: isSales ? { authorId: req.user.id } : {},
      orderBy: { createdAt: 'desc' },
      include: {
        author: { select: { id: true, name: true, role: true } },
        reviewer: { select: { id: true, name: true, role: true } },
      },
    });
    res.json({ items });
  })
);

router.post(
  '/',
  requireSalesHead,
  validate({
    body: Joi.object({
      title: Joi.string().trim().min(2).max(200).required(),
      body: Joi.string().trim().min(2).max(5000).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const note = await prisma.adminNote.create({
      data: {
        authorId: req.user.id,
        title: req.body.title,
        body: req.body.body,
        tenantId: tenant.DEFAULT_TENANT_ID,
      },
    });
    res.status(201).json(note);
  })
);

router.patch(
  '/:id/review',
  requireSuperAdmin,
  validate({
    body: Joi.object({
      status: Joi.string().valid('APPROVED', 'REJECTED').required(),
      reviewNote: Joi.string().trim().max(500).allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const existing = await prisma.adminNote.findUnique({ where: { id: req.params.id } });
    if (!existing) throw NotFound('Note not found');
    const note = await prisma.adminNote.update({
      where: { id: req.params.id },
      data: {
        status: req.body.status,
        reviewNote: req.body.reviewNote || null,
        reviewedById: req.user.id,
        reviewedAt: new Date(),
      },
    });
    res.json(note);
  })
);

module.exports = router;
