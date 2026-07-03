'use strict';

const ExcelJS = require('exceljs');
const prisma = require('../database/prisma');
const tenant = require('./tenant');

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

function istDayRange(now = new Date()) {
  const ist = new Date(now.getTime() + IST_OFFSET_MS);
  const startIstUtcMs = Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()) - IST_OFFSET_MS;
  return {
    from: new Date(startIstUtcMs),
    to: now,
    dateLabel: [
      ist.getUTCFullYear(),
      String(ist.getUTCMonth() + 1).padStart(2, '0'),
      String(ist.getUTCDate()).padStart(2, '0'),
    ].join('-'),
  };
}

function istRangeForDate(dateLabel, now = new Date()) {
  if (!dateLabel) return istDayRange(now);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateLabel));
  if (!match) return istDayRange(now);

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const startUtcMs = Date.UTC(year, month - 1, day) - IST_OFFSET_MS;
  const endUtcMs = startUtcMs + 24 * 60 * 60 * 1000 - 1;
  return {
    from: new Date(startUtcMs),
    to: new Date(Math.min(endUtcMs, now.getTime())),
    dateLabel: `${match[1]}-${match[2]}-${match[3]}`,
  };
}

function formatIst(value) {
  if (!value) return '';
  return new Intl.DateTimeFormat('en-IN', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(new Date(value));
}

function formatDuration(seconds) {
  if (!seconds && seconds !== 0) return '';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return h ? `${h}h ${m}m ${s}s` : `${m}m ${s}s`;
}

async function fetchCalls({ from, to, tenantId = null }) {
  return prisma.telecallerCall.findMany({
    where: {
      createdAt: { gte: from, lte: to },
      ...(tenantId ? { agent: { tenantId } } : {}),
    },
    orderBy: { createdAt: 'asc' },
    include: {
      agent: { select: { id: true, name: true, userId: true, email: true, phone: true, tenantId: true } },
      lead: { select: { id: true, name: true, phone: true, company: true, status: true, tenantId: true } },
    },
  });
}

async function buildWorkbook({ calls, title, from, to }) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'MyTaskKing';
  workbook.created = new Date();

  const summary = workbook.addWorksheet('Summary');
  const totalDuration = calls.reduce((sum, c) => sum + (c.durationSec || 0), 0);
  const uniqueAgents = new Set(calls.map((c) => c.agentId)).size;
  const recorded = calls.filter((c) => c.recordingUrl).length;

  summary.addRows([
    ['Report', title],
    ['From', formatIst(from)],
    ['To', formatIst(to)],
    ['Total calls', calls.length],
    ['Telecallers', uniqueAgents],
    ['Total duration', formatDuration(totalDuration)],
    ['Calls with recording', recorded],
  ]);
  summary.columns = [{ width: 24 }, { width: 48 }];
  summary.getColumn(1).font = { bold: true };

  const sheet = workbook.addWorksheet('Telecaller Calls');
  sheet.columns = [
    { header: 'Call Time (IST)', key: 'createdAt', width: 24 },
    { header: 'Agent Name', key: 'agentName', width: 24 },
    { header: 'Agent User ID', key: 'agentUserId', width: 18 },
    { header: 'Agent Phone', key: 'agentPhone', width: 18 },
    { header: 'Lead Name', key: 'leadName', width: 24 },
    { header: 'Lead Company', key: 'leadCompany', width: 24 },
    { header: 'Lead Phone', key: 'leadPhone', width: 18 },
    { header: 'Lead Status', key: 'leadStatus', width: 16 },
    { header: 'Call Outcome', key: 'callOutcome', width: 22 },
    { header: 'Duration', key: 'duration', width: 14 },
    { header: 'Notes', key: 'notes', width: 36 },
    { header: 'From Number', key: 'fromNumber', width: 18 },
    { header: 'To Number', key: 'toNumber', width: 18 },
    { header: 'Recording URL', key: 'recordingUrl', width: 48 },
    { header: 'External Call ID', key: 'externalCallId', width: 28 },
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.views = [{ state: 'frozen', ySplit: 1 }];

  for (const call of calls) {
    sheet.addRow({
      createdAt: formatIst(call.createdAt),
      agentName: call.agent?.name || '',
      agentUserId: call.agent?.userId || '',
      agentPhone: call.agent?.phone || '',
      leadName: call.lead?.name || '',
      leadCompany: call.lead?.company || '',
      leadPhone: call.lead?.phone || call.toNumber || '',
      leadStatus: call.lead?.status || '',
      callOutcome: call.status || '',
      duration: formatDuration(call.durationSec),
      notes: call.notes || '',
      fromNumber: call.fromNumber || '',
      toNumber: call.toNumber || '',
      recordingUrl: call.recordingUrl || '',
      externalCallId: call.externalCallId || '',
    });
  }

  return Buffer.from(await workbook.xlsx.writeBuffer());
}

async function buildDailyReportForUser({ user, date, scope = 'org' }) {
  const { from, to, dateLabel } = istRangeForDate(date);
  const platformAll = tenant.isPlatformSuperAdmin(user) && scope === 'all';
  const tenantId = platformAll ? null : tenant.userTenantId(user);
  const calls = await fetchCalls({ from, to, tenantId });
  const title = platformAll
    ? `All organisations telecaller call report - ${dateLabel}`
    : `Telecaller call report - ${dateLabel}`;
  const buffer = await buildWorkbook({ calls, title, from, to });
  const filename = platformAll
    ? `telecaller-calls-all-organisations-${dateLabel}.xlsx`
    : `telecaller-calls-${tenantId || 'workspace'}-${dateLabel}.xlsx`;
  return { buffer, filename, calls: calls.length, from, to, dateLabel };
}

module.exports = {
  istDayRange,
  istRangeForDate,
  buildDailyReportForUser,
};
