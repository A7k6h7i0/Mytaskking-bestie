'use strict';

const axios = require('axios');
const config = require('../config');
const logger = require('../utils/logger');
const { HttpError, BadRequest } = require('../utils/errors');

const MAX_BYTES = 25 * 1024 * 1024;

function baseUrl() {
  return (config.voiceAi?.baseUrl || 'https://ai.mytaskking.com').replace(/\/$/, '');
}

function apiKey() {
  return config.voiceAi?.apiKey || '';
}

function extensionFromUrl(url) {
  try {
    const path = new URL(url).pathname.toLowerCase();
    const match = path.match(/\.(mp3|m4a|wav|ogg|flac|webm|mp4|mpeg|mpga)$/);
    if (match) return match[1];
  } catch (_) {
    /* ignore */
  }
  return 'm4a';
}

function mimeForExt(ext) {
  const map = {
    mp3: 'audio/mpeg',
    m4a: 'audio/mp4',
    wav: 'audio/wav',
    ogg: 'audio/ogg',
    flac: 'audio/flac',
    webm: 'audio/webm',
    mp4: 'audio/mp4',
    mpeg: 'audio/mpeg',
    mpga: 'audio/mpeg',
  };
  return map[ext] || 'application/octet-stream';
}

async function downloadAudio(recordingUrl) {
  const res = await axios.get(recordingUrl, {
    responseType: 'arraybuffer',
    timeout: 120_000,
    maxContentLength: MAX_BYTES,
    maxBodyLength: MAX_BYTES,
  });
  const buffer = Buffer.from(res.data);
  if (buffer.length > MAX_BYTES) {
    throw BadRequest('Recording exceeds 25 MB limit');
  }
  return buffer;
}

async function submitVoiceFromUrl(recordingUrl) {
  const key = apiKey();
  if (!key) {
    throw new HttpError(503, 'service_unavailable', 'Voice AI API key is not configured on the server');
  }

  const audioBuffer = await downloadAudio(recordingUrl);
  const ext = extensionFromUrl(recordingUrl);
  const filename = `recording.${ext}`;
  const mime = mimeForExt(ext);

  const form = new FormData();
  form.append('apiKey', key);
  form.append('voice', new Blob([audioBuffer], { type: mime }), filename);

  const res = await fetch(`${baseUrl()}/voice/analyse`, {
    method: 'POST',
    body: form,
  });
  const body = await res.json().catch(() => ({}));
  if (res.status === 202 && body.jobID) {
    return { jobID: body.jobID, status: body.status || 'pending' };
  }
  throw new HttpError(
    res.status >= 400 && res.status < 600 ? res.status : 502,
    'voice_ai_error',
    body.error || `Voice analyse failed (${res.status})`
  );
}

async function getJobStatus(jobId) {
  const res = await fetch(`${baseUrl()}/voice/job/${encodeURIComponent(jobId)}`);
  const body = await res.json().catch(() => ({}));
  if (res.status === 200) return body;
  throw new HttpError(
    res.status >= 400 && res.status < 600 ? res.status : 502,
    'voice_ai_error',
    body.error || `Job check failed (${res.status})`
  );
}

async function healthCheck() {
  try {
    const res = await fetch(`${baseUrl()}/health`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return { ok: false };
    return res.json();
  } catch (err) {
    logger.warn({ err: err.message }, 'voiceAi.health_failed');
    return { ok: false };
  }
}

module.exports = {
  submitVoiceFromUrl,
  getJobStatus,
  healthCheck,
};
