'use strict';

const fs = require('node:fs');
const path = require('node:path');

// Try the conventional .env first, then fall back to .env.example so a fresh
// clone at least lets `node src/app.js` boot far enough to print a helpful
// error instead of crashing inside Prisma.
const dotenvPath = fs.existsSync(path.join(process.cwd(), '.env'))
  ? path.join(process.cwd(), '.env')
  : null;
require('dotenv').config(dotenvPath ? { path: dotenvPath } : undefined);

// Fail fast with a clear, actionable message when the bare minimum env is
// missing. Prisma's native error is unreadable; this catches it earlier.
function abortMissingEnv() {
  const hints = [
    '',
    '  ┌─ MyTaskKing cannot start ─────────────────────────────────────────┐',
    '  │ DATABASE_URL is not set.                                          │',
    '  │                                                                   │',
    '  │ 1. Copy the template:    cp .env.example .env                     │',
    '  │ 2. Edit .env and set:    DATABASE_URL=postgresql://…              │',
    '  │                          JWT_ACCESS_SECRET=…                      │',
    '  │                          JWT_REFRESH_SECRET=…                     │',
    '  │ 3. Start Postgres:       (deploy/docker-compose.yml has one)      │',
    '  │ 4. Re-run:               npm run dev                              │',
    '  └───────────────────────────────────────────────────────────────────┘',
    '',
  ].join('\n');
  console.error('\x1b[31m' + hints + '\x1b[0m');
  process.exit(1);
}

if (!process.env.DATABASE_URL) abortMissingEnv();

const required = (key) => {
  const value = process.env[key];
  if (value === undefined || value === '') {
    if (process.env.NODE_ENV === 'production') {
      throw new Error(`Missing required env var: ${key}`);
    }
  }
  return value;
};

const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '4000', 10),
  logLevel: process.env.LOG_LEVEL || 'info',

  databaseUrl: required('DATABASE_URL'),

  jwt: {
    accessSecret: required('JWT_ACCESS_SECRET') || 'dev-access',
    refreshSecret: required('JWT_REFRESH_SECRET') || 'dev-refresh',
    accessTtl: process.env.JWT_ACCESS_TTL || '15m',
    refreshTtl: process.env.JWT_REFRESH_TTL || '30d',
  },

  cors: {
    webOrigin: (process.env.WEB_ORIGIN || 'http://localhost:5173').split(','),
  },

  publicApiUrl: process.env.PUBLIC_API_URL || 'http://localhost:4000',

  redis: {
    url: process.env.REDIS_URL || null,
  },

  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME,
    apiKey: process.env.CLOUDINARY_API_KEY,
    apiSecret: process.env.CLOUDINARY_API_SECRET,
  },

  r2: {
    accountId: process.env.R2_ACCOUNT_ID,
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    bucket: process.env.R2_BUCKET || 'bestie-files',
    publicBaseUrl: process.env.R2_PUBLIC_BASE_URL || '',
    endpoint: process.env.R2_ACCOUNT_ID
      ? `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`
      : null,
  },

  agora: {
    appId: process.env.AGORA_APP_ID,
    appCertificate: process.env.AGORA_APP_CERTIFICATE,
    tokenTtlSeconds: parseInt(process.env.AGORA_TOKEN_TTL_SECONDS || '3600', 10),
  },

  exotel: {
    sid: process.env.EXOTEL_SID,
    apiKey: process.env.EXOTEL_API_KEY,
    apiToken: process.env.EXOTEL_API_TOKEN,
    virtualNumber: process.env.EXOTEL_VIRTUAL_NUMBER,
    callbackUrl: process.env.EXOTEL_CALLBACK_URL,
  },

  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY
      ? process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n')
      : undefined,
  },

  seed: {
    superAdminUserId: process.env.SEED_SUPER_ADMIN_USER_ID || 'superadmin',
    superAdminPassword: process.env.SEED_SUPER_ADMIN_PASSWORD || 'Change-Me-Now!',
    superAdminName: process.env.SEED_SUPER_ADMIN_NAME || 'Super Admin',
  },
};

module.exports = config;
