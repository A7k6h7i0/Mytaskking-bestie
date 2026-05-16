'use strict';

const logger = require('../utils/logger');

/**
 * AI provider — kept deliberately thin so we can swap models / vendors
 * without touching the modules that consume it. Each consumer asks for a
 * capability (`summarize`, `transcribe`, `search.rerank`, `insights.weekly`)
 * and the adapter routes it to the configured provider.
 *
 * Configured via env:
 *   AI_PROVIDER       — e.g. "anthropic" | "openai" | "noop"
 *   AI_MODEL          — provider-specific model id
 *   AI_API_KEY        — credential
 *
 * Today this ships as a noop so the platform doesn't depend on any AI vendor.
 * Wire up `anthropic` or `openai` providers when you're ready — the calling
 * code stays the same.
 */

const provider = (process.env.AI_PROVIDER || 'noop').toLowerCase();

async function summarize({ text, kind = 'general', maxTokens = 256 }) {
  if (provider === 'noop' || !process.env.AI_API_KEY) {
    logger.debug({ kind }, 'ai.summarize.noop');
    return { summary: text.slice(0, 240), provider: 'noop' };
  }
  // Hook for a real provider — implementer fills in this branch.
  throw new Error(`AI provider not implemented: ${provider}`);
}

async function transcribe({ audioUrl }) {
  if (provider === 'noop' || !process.env.AI_API_KEY) {
    logger.debug({ audioUrl }, 'ai.transcribe.noop');
    return { transcript: null, provider: 'noop' };
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
  throw new Error(`AI provider not implemented: ${provider}`);
}

module.exports = { summarize, transcribe, rerankSearch, insights, provider };
