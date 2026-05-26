'use strict';

const { Router } = require('express');
const Joi = require('joi');
const asyncHandler = require('../../utils/asyncHandler');
const validate = require('../../middleware/validate');
const { requireAuth } = require('../../middleware/auth');

const router = Router();
router.use(requireAuth);

/**
 * In-memory LRU-ish cache. Keyed by URL, 1-hour TTL, 5000-entry soft cap.
 * Lives for the lifetime of the process — small enough that cold-restart
 * cost is negligible and we don't need Redis just for this.
 */
const cache = new Map();
const CACHE_TTL_MS = 60 * 60 * 1000;
const CACHE_MAX = 5000;

function cacheGet(url) {
  const hit = cache.get(url);
  if (!hit) return null;
  if (Date.now() - hit.at > CACHE_TTL_MS) {
    cache.delete(url);
    return null;
  }
  return hit.value;
}

function cacheSet(url, value) {
  if (cache.size >= CACHE_MAX) {
    // Drop the oldest entry — Map preserves insertion order.
    const firstKey = cache.keys().next().value;
    if (firstKey) cache.delete(firstKey);
  }
  cache.set(url, { at: Date.now(), value });
}

/** Pulls a single tag value out of HTML — works for both <meta property=...
 * content=...> and `<title>...</title>`. Regex-based to avoid pulling in
 * a real HTML parser for what is, at this scale, a tiny side feature. */
function extractMeta(html, key) {
  // og:title, twitter:title, etc — match either property= or name=
  const patterns = [
    new RegExp(
      `<meta[^>]+(?:property|name)=["']${key}["'][^>]+content=["']([^"']+)["']`,
      'i',
    ),
    new RegExp(
      `<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${key}["']`,
      'i',
    ),
  ];
  for (const p of patterns) {
    const m = html.match(p);
    if (m?.[1]) return decodeEntities(m[1]).trim();
  }
  return null;
}

function decodeEntities(s) {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function originOf(url) {
  try {
    const u = new URL(url);
    return u.hostname.replace(/^www\./, '');
  } catch (_) {
    return null;
  }
}

router.get(
  '/',
  validate({
    query: Joi.object({
      url: Joi.string().uri({ scheme: ['http', 'https'] }).required(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const url = req.query.url;
    const cached = cacheGet(url);
    if (cached) return res.json(cached);

    let payload = { url, host: originOf(url) };
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 6000);
      const r = await fetch(url, {
        signal: controller.signal,
        redirect: 'follow',
        headers: {
          // Cloudflare, Reddit, Twitter, etc. block bare bot UAs.
          'User-Agent':
            'Mozilla/5.0 (compatible; MyTaskKingBot/1.0; +https://mytaskking.com/bot)',
          'Accept': 'text/html,application/xhtml+xml',
        },
      });
      clearTimeout(timeout);
      if (!r.ok) {
        payload.error = `HTTP ${r.status}`;
        cacheSet(url, payload);
        return res.json(payload);
      }
      // Read at most 200 kB — OG tags always live in <head>, anything past
      // that is body content we don't need and don't want to pay for.
      const buf = Buffer.alloc(200_000);
      const reader = r.body.getReader();
      let offset = 0;
      while (offset < buf.length) {
        const { value, done } = await reader.read();
        if (done) break;
        const take = Math.min(value.length, buf.length - offset);
        value.copy(buf, offset, 0, take);
        offset += take;
        if (offset >= buf.length) {
          try { await reader.cancel(); } catch (_) {}
          break;
        }
      }
      const html = buf.slice(0, offset).toString('utf8');
      const title =
        extractMeta(html, 'og:title') ||
        extractMeta(html, 'twitter:title') ||
        (html.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1]?.trim() || null);
      const description =
        extractMeta(html, 'og:description') ||
        extractMeta(html, 'twitter:description') ||
        extractMeta(html, 'description');
      const image =
        extractMeta(html, 'og:image') ||
        extractMeta(html, 'twitter:image') ||
        extractMeta(html, 'twitter:image:src');
      payload = {
        url,
        host: originOf(url),
        title: title ? decodeEntities(title) : null,
        description: description ? decodeEntities(description) : null,
        image,
      };
    } catch (err) {
      payload.error = err.message || 'fetch_failed';
    }
    cacheSet(url, payload);
    res.json(payload);
  })
);

module.exports = router;
