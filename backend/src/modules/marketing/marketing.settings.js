'use strict';

const prisma = require('../../database/prisma');
const tenant = require('../../services/tenant');

const DEFAULTS = {
  visitSelfieRequired: true,
  blinkSelfieRequired: true,
  outletCreationApprovalRequired: true,
  gpsIntervalMovingSeconds: 120,
  autoVisitDurationMinutes: 0,
};

const KEYS = Object.keys(DEFAULTS);

function scopedFieldScope(req) {
  return tenant.orgSettingScope(req, 'field');
}

async function getFieldSettings(req) {
  const scope = scopedFieldScope(req);
  const rows = await prisma.workspaceSetting.findMany({
    where: { scope, key: { in: KEYS } },
  });
  const out = { ...DEFAULTS };
  for (const row of rows) {
    if (row.key in out) out[row.key] = row.value;
  }
  return out;
}

module.exports = { DEFAULTS, KEYS, getFieldSettings, scopedFieldScope };
