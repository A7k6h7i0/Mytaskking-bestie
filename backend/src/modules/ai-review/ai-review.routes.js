'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth, requireAdmin } = require('../../middleware/auth');
const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');
const voiceAi = require('../../services/voiceAi');
const { NotFound } = require('../../utils/errors');

const router = Router();
router.use(requireAuth, requireAdmin);

function telecallerWhere(req) {
  const platformView =
    tenant.isPlatformSuperAdmin(req.user) && req.query.scope === 'platform';
  const base = { recordingUrl: { not: null } };
  if (platformView) return base;
  return {
    ...base,
    agent: { tenantId: tenant.userTenantId(req.user) },
  };
}

router.get(
  '/recordings',
  validate({
    query: Joi.object({
      scope: Joi.string().valid('org', 'platform').default('org'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const items = await prisma.telecallerCall.findMany({
      where: telecallerWhere(req),
      include: {
        lead: { select: { id: true, name: true, phone: true, company: true } },
        agent: { select: { id: true, name: true, phone: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });

    res.json({
      items: items.map((tc) => ({
        id: tc.id,
        recordingUrl: tc.recordingUrl,
        fromNumber: tc.fromNumber,
        toNumber: tc.toNumber,
        status: tc.status,
        durationSec: tc.durationSec,
        startedAt: tc.startedAt,
        endedAt: tc.endedAt,
        createdAt: tc.createdAt,
        notes: tc.notes,
        lead: tc.lead
          ? {
              id: tc.lead.id,
              name: tc.lead.name,
              phone: tc.lead.phone,
              company: tc.lead.company,
            }
          : null,
        agent: tc.agent
          ? { id: tc.agent.id, name: tc.agent.name, phone: tc.agent.phone }
          : null,
      })),
    });
  })
);

router.post(
  '/analyse',
  validate({
    body: Joi.object({
      callId: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const where = telecallerWhere(req);
    const call = await prisma.telecallerCall.findFirst({
      where: { ...where, id: req.body.callId },
      select: { id: true, recordingUrl: true },
    });
    if (!call?.recordingUrl) throw NotFound('Telecaller recording not found');
    const result = await voiceAi.submitVoiceFromUrl(call.recordingUrl);
    res.status(202).json(result);
  })
);

router.get(
  '/job/:jobId',
  validate({
    params: Joi.object({
      jobId: Joi.string().required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const result = await voiceAi.getJobStatus(req.params.jobId);
    if (result.status === 'completed' && result.output) {
      return res.json({
        jobID: result.jobID,
        status: 'completed',
        output: {
          text: result.output.text ?? '',
          intent: result.output.intent ?? '',
          confidence: result.output.confidence ?? 0,
        },
      });
    }
    if (result.status === 'failed') {
      return res.status(200).json({
        jobID: result.jobID,
        status: 'failed',
        error: result.error || 'Analysis failed',
      });
    }
    res.json({ jobID: result.jobID, status: result.status || 'pending' });
  })
);

router.get(
  '/health',
  asyncHandler(async (_req, res) => {
    const health = await voiceAi.healthCheck();
    res.json({
      configured: !!process.env.VOICE_AI_API_KEY,
      server: health,
    });
  })
);

module.exports = router;
