'use strict';

const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');

const DEFAULTS = {
  gpsEnabled: true,
  gpsIntervalSeconds: 300,
};

const INTERVAL_OPTIONS = [120, 300, 600, 900, 1800, 3600];
const KEYS = Object.keys(DEFAULTS);

function scopedScope(req) {
  return tenant.orgSettingScope(req, 'loginActivity');
}

async function getSettings(req) {
  const scope = scopedScope(req);
  const rows = await prisma.workspaceSetting.findMany({
    where: { scope, key: { in: KEYS } },
  });
  const out = { ...DEFAULTS };
  for (const row of rows) {
    if (row.key in out) out[row.key] = row.value;
  }
  const interval = Number(out.gpsIntervalSeconds);
  out.gpsIntervalSeconds = INTERVAL_OPTIONS.includes(interval) ? interval : DEFAULTS.gpsIntervalSeconds;
  out.gpsEnabled = out.gpsEnabled !== false;
  return out;
}

module.exports = { DEFAULTS, KEYS, INTERVAL_OPTIONS, getSettings, scopedScope };
