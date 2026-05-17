'use strict';

const logger = require('../utils/logger');
const axios = require('axios');

/**
 * AI provider — kept deliberately thin so we can swap models / vendors
 * without touching the modules that consume it. Each consumer asks for a
 * capability (`summarize`, `transcribe`, `search.rerank`, `insights.weekly`)
 * and the adapter routes it to the configured provider.
 *
 * Configured via env:
 *   AI_PROVIDER       — e.g. "gemini" | "anthropic" | "openai" | "noop"
 *   AI_MODEL          — provider-specific model id
 *   AI_API_KEY        — credential
 *
 * Today this ships as a noop so the platform doesn't depend on any AI vendor.
 * Wire up `anthropic` or `openai` providers when you're ready — the calling
 * code stays the same.
 */

const provider = (process.env.AI_PROVIDER || 'noop').toLowerCase();
const apiKey = process.env.AI_API_KEY;
const model = process.env.AI_MODEL || 'gemini-2.5-flash';
const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

function extractText(payload) {
  const candidates = payload?.candidates || [];
  const parts = candidates
    .flatMap((candidate) => candidate?.content?.parts || [])
    .map((part) => part?.text)
    .filter(Boolean);
  return parts.join('\n').trim();
}

function safeJsonParse(text, fallback) {
  try {
    return JSON.parse(text);
  } catch {
    const cleaned = String(text || '')
      .trim()
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/i, '');
    try {
      return JSON.parse(cleaned);
    } catch {
      return fallback;
    }
  }
}

function normalizeSummary(text, fallback) {
  const summary = String(text || '').replace(/\s+/g, ' ').trim();
  if (!summary || summary.length < 50 || summary.split(/\s+/).length < 8) return fallback;
  return summary;
}

function parseBulletsFromText(text) {
  return String(text || '')
    .split('\n')
    .map((line) => line.replace(/^[-*•\d.\s]+/, '').trim())
    .filter(Boolean)
    .slice(0, 5);
}

async function geminiGenerate({ prompt, maxOutputTokens = 256, responseMimeType }) {
  const url = `${GEMINI_BASE_URL}/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const body = {
    contents: [
      {
        role: 'user',
        parts: [{ text: prompt }],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens,
      ...(responseMimeType ? { responseMimeType } : {}),
    },
  };
  const { data } = await axios.post(url, body, {
    timeout: 45_000,
    headers: { 'Content-Type': 'application/json' },
  });
  return extractText(data);
}

async function summarize({ text, kind = 'general', maxTokens = 256 }) {
  if (provider === 'noop' || !process.env.AI_API_KEY) {
    logger.debug({ kind }, 'ai.summarize.noop');
    return { summary: text.slice(0, 240), provider: 'noop' };
  }
  if (provider === 'gemini') {
    const prompt = [
      `You are summarizing ${kind} content for a business workspace product.`,
      'Write one useful summary paragraph in plain English.',
      'Keep it concise but complete: 2 to 4 sentences, around 60 to 110 words.',
      'Include the most important concrete facts and avoid filler, markdown, or headings.',
      '',
      'Content:',
      text,
    ].join('\n');
    const fallback = text.slice(0, 240);
    const summary = await geminiGenerate({ prompt, maxOutputTokens: Math.max(maxTokens, 128) });
    return { summary: normalizeSummary(summary, fallback), provider: 'gemini', model };
  }
  throw new Error(`AI provider not implemented: ${provider}`);
}

async function transcribe({ audioUrl }) {
  if (provider === 'noop' || !process.env.AI_API_KEY) {
    logger.debug({ audioUrl }, 'ai.transcribe.noop');
    return { transcript: null, provider: 'noop' };
  }
  if (provider === 'gemini') {
    logger.warn({ audioUrl }, 'ai.transcribe.unsupported.gemini');
    return { transcript: null, provider: 'gemini', model, unsupported: true };
  }
  throw new Error(`AI provider not implemented: ${provider}`);
}

/**
 * Re-rank search hits — given a query and a list of candidate items, return
 * the items sorted by AI-judged relevance. The search module can wrap its
 * own results with this when AI is enabled.
 */
async function rerankSearch({ query, items }) {
  if (provider === 'noop' || !process.env.AI_API_KEY) return items;
  if (provider === 'gemini') {
    if (!Array.isArray(items) || items.length <= 1) return items;
    const prompt = [
      'You are ranking candidate search results for a business workspace application.',
      'Return strict JSON only in this format: {"order":[0,2,1]}.',
      'The "order" array must contain every item index exactly once, ranked most relevant first.',
      `User query: ${query}`,
      'Candidates:',
      JSON.stringify(
        items.map((item, index) => ({
          index,
          title: item?.title || item?.name || item?.subject || '',
          description: item?.description || item?.summary || item?.notes || '',
          type: item?.type || item?.kind || '',
        }))
      ),
    ].join('\n');

    const text = await geminiGenerate({
      prompt,
      maxOutputTokens: 256,
      responseMimeType: 'application/json',
    });
    const parsed = safeJsonParse(text, null);
    const order = Array.isArray(parsed?.order) ? parsed.order : [];
    if (order.length !== items.length) return items;
    const mapped = order
      .map((idx) => items[idx])
      .filter((item) => item !== undefined);
    return mapped.length === items.length ? mapped : items;
  }
  throw new Error(`AI provider not implemented: ${provider}`);
}

/**
 * Generate insights from a payload — used by the dashboard "insights" widget
 * once enabled. Same contract regardless of provider.
 */
async function insights({ scope, payload }) {
  if (provider === 'noop' || !process.env.AI_API_KEY) {
    return { bullets: [], provider: 'noop' };
  }
  if (provider === 'gemini') {
    const prompt = [
      'You are preparing short operational insights for a business admin dashboard.',
      'Write 2 to 5 short bullets.',
      'Each bullet must be concise, practical, and grounded only in the provided payload.',
      'Mention notable trends, risks, or opportunities when they are visible.',
      'Return plain text only, one bullet per line, and start each line with "- ".',
      `Scope: ${scope}`,
      `Payload: ${JSON.stringify(payload)}`,
    ].join('\n');
    const text = await geminiGenerate({
      prompt,
      maxOutputTokens: 512,
    });
    const bullets = parseBulletsFromText(text);
    return { bullets, provider: 'gemini', model };
  }
  throw new Error(`AI provider not implemented: ${provider}`);
}

module.exports = { summarize, transcribe, rerankSearch, insights, provider };
