'use strict';

const helmet = require('helmet');
const cache = require('../services/cache');
const { TooMany, Forbidden } = require('../utils/errors');

/**
 * Production-grade security middleware bundle.
 *
 *   app.use(security.helmet());
 *   app.use('/api/v1/auth', security.bruteForce({ key: 'auth' }));
 *
 * What's included:
 *   • CSP with a deny-by-default policy that permits the assets MyTaskKing
 *     actually uses (Cloudinary images, R2 files, Google Fonts).
 *   • HSTS — long-lived, includeSubDomains, preload.
 *   • frameguard, noSniff, referrerPolicy.
 *   • A brute-force middleware backed by the cache service. Counts failed
 *     attempts per (ip, key); after `threshold` failures within `window`
 *     seconds, the client is blocked for `block` seconds.
 *   • A suspicious-activity recorder hook — modules call `flagSuspicious(req, reason)`
 *     on heuristic hits (impossible travel, mass-delete attempts, etc).
 *
 * Cookie policy lives elsewhere (we use bearer tokens, not cookies). If you
 * add cookie sessions, enable `cookie: { secure: true, httpOnly: true, sameSite: 'lax' }`.
 */

function helmetBundle() {
  return helmet({
    contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'", 'https://unpkg.com'],   // Swagger UI is loaded from unpkg
        styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com', 'https://unpkg.com'],
        fontSrc: ["'self'", 'https://fonts.gstatic.com', 'data:'],
        imgSrc: ["'self'", 'data:', 'blob:', 'https://res.cloudinary.com', 'https://*.r2.cloudflarestorage.com', 'https://*.r2.dev'],
        mediaSrc: ["'self'", 'blob:', 'https://res.cloudinary.com', 'https://*.r2.cloudflarestorage.com'],
        connectSrc: ["'self'", 'https:', 'wss:'],
        objectSrc: ["'none'"],
        frameAncestors: ["'none'"],
      },
    },
    hsts: { maxAge: 31_536_000, includeSubDomains: true, preload: true },
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    crossOriginOpenerPolicy: { policy: 'same-origin' },
    crossOriginResourcePolicy: { policy: 'same-site' },
  });
}

/**
 * Brute-force protection middleware. Use on auth endpoints.
 * `bruteForce({ key: 'auth', threshold: 5, window: 300, block: 900 })`
 */
function bruteForce({ key = 'default', threshold = 8, window = 300, block = 900 } = {}) {
  return async (req, _res, next) => {
    const identifier = (req.body && req.body.userId) || req.ip;
    const ckey = `bf:${key}:${identifier}`;
    const blockedKey = `bf:blocked:${key}:${identifier}`;
    try {
      const blocked = await cache.get(blockedKey);
      if (blocked) return next(TooMany('Too many failed attempts. Try again later.'));
      // We can't increment on success — we increment on next() failures via the
      // route's catch path. So we tag the request with a helper to call later.
      req.bruteForce = {
        async fail() {
          const n = await cache.incr(ckey, window);
          if (n >= threshold) await cache.set(blockedKey, true, block);
        },
        async pass() {
          await cache.del(ckey).catch(() => {});
        },
      };
      next();
    } catch (err) {
      next();
    }
  };
}

/** Record a suspicious event and rate-block by ip if it crosses a threshold. */
async function flagSuspicious(req, reason) {
  const ip = req.ip || 'unknown';
  const key = `sus:${ip}`;
  const n = await cache.incr(key, 3600);
  if (n >= 10) await cache.set(`sus:blocked:${ip}`, reason, 3600);
}

/**
 * Field-level encryption helper using node's built-in crypto. AES-256-GCM
 * with a 12-byte IV and a 16-byte auth tag.
 *
 *   const enc = security.encrypt('secret value');
 *   const dec = security.decrypt(enc);
 *
 * Reads the key from `FIELD_ENCRYPTION_KEY` (32-byte hex). When unset, both
 * functions throw — refuse to silently store plaintext where the caller
 * expected encryption.
 */
function loadKey() {
  const hex = process.env.FIELD_ENCRYPTION_KEY;
  if (!hex) throw new Error('FIELD_ENCRYPTION_KEY not set');
  const buf = Buffer.from(hex, 'hex');
  if (buf.length !== 32) throw new Error('FIELD_ENCRYPTION_KEY must be 32 bytes (64 hex chars)');
  return buf;
}

function encrypt(plaintext) {
  const crypto = require('crypto');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', loadKey(), iv);
  const enc = Buffer.concat([cipher.update(String(plaintext), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1:${iv.toString('base64')}:${tag.toString('base64')}:${enc.toString('base64')}`;
}

function decrypt(envelope) {
  const crypto = require('crypto');
  const parts = String(envelope).split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') throw new Error('bad envelope');
  const [, ivB64, tagB64, dataB64] = parts;
  const decipher = crypto.createDecipheriv('aes-256-gcm', loadKey(), Buffer.from(ivB64, 'base64'));
  decipher.setAuthTag(Buffer.from(tagB64, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(dataB64, 'base64')), decipher.final()]).toString('utf8');
}

module.exports = { helmet: helmetBundle, bruteForce, flagSuspicious, encrypt, decrypt };
