'use strict';

const { Router } = require('express');
const Joi = require('joi');
const multer = require('multer');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const cloudinary = require('../../services/cloudinary');
const r2 = require('../../services/r2');
const fileAccess = require('../../services/fileAccess');
const tenant = require('../../services/tenant');
const audit = require('../../services/audit');
const logger = require('../../utils/logger');
const { BadRequest, Forbidden } = require('../../utils/errors');

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } });

router.use(requireAuth);

// Direct upload — images go to Cloudinary, everything else (PDFs, docs) goes to R2.
router.post(
  '/upload',
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) throw BadRequest('No file uploaded');
    const isImage = req.file.mimetype.startsWith('image/');

    // Prefer Cloudinary for images (gives width/height + transforms), but fall
    // back to R2 when Cloudinary isn't configured — otherwise an image upload
    // 500'd ("Internal server error") on servers that only have R2 set up.
    const uploadToR2 = async () => {
      const safeName = (req.file.originalname || 'file').replace(/[^\w.-]/g, '_');
      const key = `files/${Date.now()}-${safeName}`;
      const put = await r2.putBuffer({ buffer: req.file.buffer, key, contentType: req.file.mimetype });
      return prisma.fileAsset.create({
        data: tenant.withTenant(req, {
          backend: 'R2',
          url: put.url,
          key: put.key,
          mimeType: req.file.mimetype,
          size: req.file.size,
          originalName: req.file.originalname,
          uploadedById: req.user.id,
        }),
      });
    };

    let asset;
    if (isImage && cloudinary.isConfigured()) {
      try {
        const result = await cloudinary.uploadBuffer(req.file.buffer, { folder: 'bestie/chat' });
        asset = await prisma.fileAsset.create({
          data: tenant.withTenant(req, {
            backend: 'CLOUDINARY',
            url: result.secure_url,
            key: result.public_id,
            mimeType: req.file.mimetype,
            size: req.file.size,
            width: result.width || null,
            height: result.height || null,
            originalName: req.file.originalname,
            uploadedById: req.user.id,
          }),
        });
      } catch (err) {
        logger.warn({ err: err.message, originalName: req.file.originalname }, 'files.upload.cloudinary_failed_falling_back_to_r2');
        if (!r2.isConfigured()) throw err;
        asset = await uploadToR2();
      }
    } else if (r2.isConfigured()) {
      asset = await uploadToR2();
    } else {
      throw BadRequest(
        'File storage is not configured on the server. Set Cloudinary or R2 credentials.'
      );
    }
    res.status(201).json(asset);
  })
);

// Signed-upload bundles so clients can upload directly to Cloudinary / R2.
router.post(
  '/sign/cloudinary',
  asyncHandler(async (_req, res) => {
    const params = cloudinary.signUploadParams();
    if (!params) throw BadRequest('Cloudinary not configured');
    res.json(params);
  })
);

router.post(
  '/sign/r2',
  validate({
    body: Joi.object({
      filename: Joi.string().required(),
      contentType: Joi.string().required(),
      folder: Joi.string().default('files'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const signed = await r2.presignPut(req.body);
    if (!signed) throw BadRequest('R2 not configured');
    res.json(signed);
  })
);

// After client-side upload completes, register the asset.
router.post(
  '/register',
  validate({
    body: Joi.object({
      backend: Joi.string().valid('CLOUDINARY', 'R2').required(),
      url: Joi.string().uri().required(),
      key: Joi.string().allow('', null),
      mimeType: Joi.string().required(),
      size: Joi.number().integer().min(0).required(),
      width: Joi.number().integer().allow(null),
      height: Joi.number().integer().allow(null),
      originalName: Joi.string().allow('', null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const asset = await prisma.fileAsset.create({
      data: tenant.withTenant(req, { ...req.body, uploadedById: req.user.id }),
    });
    res.status(201).json(asset);
  })
);

router.get(
  '/:id/signed-url',
  asyncHandler(async (req, res) => {
    const asset = await prisma.fileAsset.findUnique({ where: { id: req.params.id } });
    if (!asset) throw BadRequest('Not found');
    tenant.assertResourceInOrg(req, asset.tenantId);
    const allowed = await fileAccess.canAccess({ file: asset, user: req.user });
    if (!allowed) throw Forbidden('You do not have access to this file');
    audit.record({ kind: 'file.downloaded', entity: 'file', entityId: asset.id, req });
    await prisma.fileDownload
      .create({
        data: {
          fileId: asset.id,
          userId: req.user.id,
          ip: req.ip,
          userAgent: req.headers['user-agent'] || null,
        },
      })
      .catch(() => {});
    if (asset.backend === 'R2' && asset.key) {
      const url = await r2.presignGet({ key: asset.key });
      return res.json({ url });
    }
    res.json({ url: asset.url });
  })
);

// File versioning — upload a new version of an existing file.
router.post(
  '/:id/versions',
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) throw BadRequest('No file uploaded');
    const asset = await prisma.fileAsset.findUnique({ where: { id: req.params.id } });
    if (!asset) throw BadRequest('File not found');
    tenant.assertResourceInOrg(req, asset.tenantId);

    const next = asset.currentVersion + 1;
    const isImage = req.file.mimetype.startsWith('image/');
    let url, key;
    if (isImage) {
      const result = await cloudinary.uploadBuffer(req.file.buffer, { folder: 'bestie/versions' });
      url = result.secure_url;
      key = result.public_id;
    } else {
      const k = `files/v${next}/${Date.now()}-${req.file.originalname}`;
      const put = await r2.putBuffer({ buffer: req.file.buffer, key: k, contentType: req.file.mimetype });
      url = put.url;
      key = put.key;
    }

    const [version] = await prisma.$transaction([
      prisma.fileVersion.create({
        data: {
          fileId: asset.id,
          version: next,
          url,
          key,
          size: req.file.size,
          uploadedById: req.user.id,
        },
      }),
      prisma.fileAsset.update({
        where: { id: asset.id },
        data: { currentVersion: next, url, key, size: req.file.size, mimeType: req.file.mimetype },
      }),
    ]);
    res.status(201).json(version);
  })
);

router.get(
  '/:id/versions',
  asyncHandler(async (req, res) => {
    const asset = await prisma.fileAsset.findUnique({ where: { id: req.params.id } });
    if (!asset) throw BadRequest('File not found');
    tenant.assertResourceInOrg(req, asset.tenantId);
    const items = await prisma.fileVersion.findMany({
      where: { fileId: req.params.id },
      orderBy: { version: 'desc' },
    });
    res.json({ items });
  })
);

router.patch(
  '/:id/category',
  asyncHandler(async (req, res) => {
    const existing = await prisma.fileAsset.findUnique({ where: { id: req.params.id } });
    if (!existing) throw BadRequest('File not found');
    tenant.assertResourceInOrg(req, existing.tenantId);
    const asset = await prisma.fileAsset.update({
      where: { id: req.params.id },
      data: { category: req.body.category || null, previewUrl: req.body.previewUrl || undefined },
    });
    res.json(asset);
  })
);

// ---- file access policy + grants ----

router.put(
  '/:id/policy',
  validate({
    body: Joi.object({
      visibility: Joi.string().valid('PRIVATE', 'CHANNEL', 'TENANT', 'PUBLIC'),
      channelId: Joi.string().allow(null, ''),
      expiresAt: Joi.date().iso().allow(null),
      watermark: Joi.boolean(),
      preventDownload: Joi.boolean(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const asset = await prisma.fileAsset.findUnique({ where: { id: req.params.id } });
    if (!asset) throw BadRequest('File not found');
    tenant.assertResourceInOrg(req, asset.tenantId);
    const policy = await fileAccess.setPolicy({ fileId: req.params.id, data: req.body });
    audit.record({ kind: 'file.policy_changed', entity: 'file', entityId: req.params.id, payload: req.body, req });
    res.json(policy);
  })
);

router.post(
  '/:id/grants',
  validate({
    body: Joi.object({
      userId: Joi.string().required(),
      canDownload: Joi.boolean(),
      expiresAt: Joi.date().iso().allow(null),
    }),
  }),
  asyncHandler(async (req, res) => {
    const asset = await prisma.fileAsset.findUnique({ where: { id: req.params.id } });
    if (!asset) throw BadRequest('File not found');
    tenant.assertResourceInOrg(req, asset.tenantId);
    await tenant.assertUserSameTenant(req, req.body.userId);
    const grant = await fileAccess.grant({ fileId: req.params.id, ...req.body });
    audit.record({ kind: 'file.granted', entity: 'file', entityId: req.params.id, payload: { userId: req.body.userId }, req });
    res.status(201).json(grant);
  })
);

router.delete(
  '/:id/grants/:userId',
  asyncHandler(async (req, res) => {
    await fileAccess.revoke({ fileId: req.params.id, userId: req.params.userId });
    res.status(204).end();
  })
);

// Per-file access log (for the file detail panel)
router.get(
  '/:id/access-log',
  asyncHandler(async (req, res) => {
    const items = await prisma.fileDownload.findMany({
      where: { fileId: req.params.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    res.json({ items });
  })
);

module.exports = router;
