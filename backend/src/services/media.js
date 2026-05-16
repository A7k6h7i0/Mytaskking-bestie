'use strict';

const prisma = require('../database/prisma');
const queue = require('./queue');
const logger = require('../utils/logger');

/**
 * Media processing pipeline.
 *
 * The hot path (POST /files/upload) stays fast: persist the FileAsset, then
 * fire-and-forget a MediaJob for the heavy work (compression, thumbnail,
 * PDF preview, transcode). A worker process picks up the job; the file row
 * gets updated with `previewUrl` / `width` / `height` when the job finishes.
 *
 * Workers can run in the same process for dev (in-memory queue) or in a
 * dedicated worker process (`node src/worker.js`) when BullMQ is configured.
 */

async function enqueueJob({ kind, fileId, input = {} }) {
  const job = await prisma.mediaJob.create({
    data: { kind, fileId: fileId || null, input, status: 'QUEUED' },
  });
  await queue.enqueue('media', { jobId: job.id }, { attempts: 5 });
  return job;
}

// Concrete processors. Each receives the persisted MediaJob row. They should
// be idempotent (a retry shouldn't double-write the FileAsset).
async function processImageCompress(job) {
  // Real implementation calls sharp or runs through Cloudinary's eager params.
  // Today we just record that we'd have done it.
  logger.info({ jobId: job.id, fileId: job.fileId }, 'media.image_compress.noop');
  return { ok: true };
}

async function processImageThumbnail(job) {
  if (!job.fileId) return { ok: false };
  // Stub — wire to Cloudinary transform URL once enabled.
  const file = await prisma.fileAsset.findUnique({ where: { id: job.fileId } });
  const thumb = file?.url ? file.url.replace('/upload/', '/upload/w_240,h_240,c_fill,q_auto,f_auto/') : null;
  if (thumb) await prisma.fileAsset.update({ where: { id: job.fileId }, data: { previewUrl: thumb } });
  return { ok: !!thumb, thumb };
}

async function processPdfPreview(job) {
  if (!job.fileId) return { ok: false };
  // Real impl would render page 1 with `pdf-poppler` or call Cloudinary's
  // PDF-to-image transform. Stub for now.
  logger.info({ jobId: job.id }, 'media.pdf_preview.noop');
  return { ok: true };
}

async function processAudioOptimize(job) {
  logger.info({ jobId: job.id }, 'media.audio_optimize.noop');
  return { ok: true };
}

async function processVideoTranscode(job) {
  logger.info({ jobId: job.id }, 'media.video_transcode.noop');
  return { ok: true };
}

async function processChunkReassembly(job) {
  // For very large uploads, the client posts chunks under `input.chunkKeys`
  // and the worker reassembles them into a single R2 object. Stub.
  logger.info({ jobId: job.id }, 'media.chunk_reassembly.noop');
  return { ok: true };
}

const HANDLERS = {
  IMAGE_COMPRESS: processImageCompress,
  IMAGE_THUMBNAIL: processImageThumbnail,
  PDF_PREVIEW: processPdfPreview,
  AUDIO_OPTIMIZE: processAudioOptimize,
  VIDEO_TRANSCODE: processVideoTranscode,
  CHUNK_REASSEMBLY: processChunkReassembly,
};

function registerWorker() {
  queue.process('media', async (job) => {
    const row = await prisma.mediaJob.findUnique({ where: { id: job.data.jobId } });
    if (!row) return;
    await prisma.mediaJob.update({ where: { id: row.id }, data: { status: 'RUNNING', startedAt: new Date(), attempts: { increment: 1 } } });
    try {
      const handler = HANDLERS[row.kind];
      const output = handler ? await handler(row) : { ok: false, error: 'no_handler' };
      await prisma.mediaJob.update({ where: { id: row.id }, data: { status: 'DONE', output, finishedAt: new Date() } });
    } catch (err) {
      await prisma.mediaJob.update({ where: { id: row.id }, data: { status: 'FAILED', error: err.message, finishedAt: new Date() } });
      throw err;
    }
  });
  logger.info('media.worker.registered');
}

module.exports = { enqueueJob, registerWorker };
