'use strict';

const ExcelJS = require('exceljs');
const prisma = require('../../database/prisma');
const exotel = require('../../services/exotel');
const config = require('../../config');
const tenant = require('../../services/tenant');
const { NotFound, BadRequest, Forbidden } = require('../../utils/errors');

const CALL_OUTCOMES = new Set([
  'REACHABLE',
  'NO_ANSWER',
  'NOT_RESPONDED',
  'BUSY',
  'SWITCHED_OFF',
  'FOLLOWUP_REQUIRED',
  'WRONG_NUMBER',
  'NOT_INTERESTED',
]);

function normalizePhoneNumber(value) {
  return String(value || '').trim().replace(/[^\d+]/g, '');
}

/**
 * Accept +917076119520, 07076119520, 7076119520 and general E.164-ish numbers.
 * Returns normalized string or null if invalid.
 */
function normalizeLeadPhone(value) {
  const trimmed = String(value || '')
    .trim()
    .replace(/[\s\-().]/g, '');
  if (!trimmed) return null;
  const hasPlus = trimmed.startsWith('+');
  const digits = trimmed.replace(/[^\d]/g, '');
  if (digits.length < 8 || digits.length > 15) return null;

  if (digits.length === 10 && /^[6-9]\d{9}$/.test(digits)) return digits;
  if (digits.length === 11 && digits.startsWith('0')) {
    const rest = digits.slice(1);
    if (/^[6-9]\d{9}$/.test(rest)) return rest;
  }
  if (digits.length === 12 && digits.startsWith('91')) {
    const rest = digits.slice(2);
    if (/^[6-9]\d{9}$/.test(rest)) return `+91${rest}`;
  }
  if (hasPlus && digits.length >= 8 && digits.length <= 15) return `+${digits}`;
  if (digits.length >= 8 && digits.length <= 15) return digits;
  return null;
}

function leadStatusForOutcome(outcome, currentStatus) {
  if (outcome === 'REACHABLE') return currentStatus === 'NEW' ? 'CONTACTED' : currentStatus;
  if (outcome === 'FOLLOWUP_REQUIRED') return 'FOLLOWUP';
  if (outcome === 'NOT_INTERESTED' || outcome === 'WRONG_NUMBER') return 'LOST';
  if (['NO_ANSWER', 'NOT_RESPONDED', 'BUSY', 'SWITCHED_OFF'].includes(outcome)) {
    return currentStatus === 'NEW' ? 'CONTACTED' : currentStatus;
  }
  return currentStatus;
}

function startOfUtcDay(dateLabel) {
  const [year, month, day] = String(dateLabel).split('-').map(Number);
  if (!year || !month || !day) throw BadRequest('Invalid date');
  return new Date(Date.UTC(year, month - 1, day));
}

function workingDates({ startDate, endDate, workingDays }) {
  const days = new Set((workingDays || [1, 2, 3, 4, 5, 6]).map(Number));
  const start = startOfUtcDay(startDate);
  const end = startOfUtcDay(endDate);
  if (end < start) throw BadRequest('End date must be after start date');

  const dates = [];
  for (const cursor = new Date(start); cursor <= end; cursor.setUTCDate(cursor.getUTCDate() + 1)) {
    if (days.has(cursor.getUTCDay())) {
      dates.push(new Date(cursor));
    }
  }
  return dates;
}

function cellText(value) {
  if (value == null) return '';
  if (value.text) return String(value.text).trim();
  if (value.hyperlink && value.text) return String(value.text).trim();
  if (Array.isArray(value.richText)) {
    return value.richText.map((part) => part.text || '').join('').trim();
  }
  if (value.result != null) return String(value.result).trim();
  return String(value).trim();
}

function splitCsvLine(line) {
  const out = [];
  let current = '';
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === '"' && line[i + 1] === '"') {
      current += '"';
      i += 1;
    } else if (char === '"') {
      quoted = !quoted;
    } else if (char === ',' && !quoted) {
      out.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  out.push(current.trim());
  return out;
}

function rowToRecord(values, headers = null) {
  const normalizedHeaders = headers?.map((h) => String(h || '').trim().toLowerCase());
  const at = (name, fallbackIndex) => {
    if (normalizedHeaders) {
      const index = normalizedHeaders.findIndex((header) => header === name);
      if (index >= 0) return values[index] || '';
    }
    return values[fallbackIndex] || '';
  };

  return {
    name: at('name', 0) || at('customer name', 0) || at('lead name', 0),
    phone: at('phone', 1) || at('mobile', 1) || at('phone number', 1),
    company: at('company', 2),
    email: at('email', 3),
    source: at('source', 5),
    notes: at('notes', 4) || at('remark', 4) || at('remarks', 4),
  };
}

function fileExtension(file) {
  const originalName = String(file?.originalname || '').toLowerCase();
  const match = originalName.match(/\.([a-z0-9]+)$/);
  return match ? match[1] : '';
}

function isCsvUpload(file) {
  const ext = fileExtension(file);
  const mimetype = String(file?.mimetype || '').toLowerCase();
  return ext === 'csv' || mimetype === 'text/csv' || mimetype === 'application/csv';
}

function isOpenXmlExcelUpload(file) {
  const ext = fileExtension(file);
  const mimetype = String(file?.mimetype || '').toLowerCase();
  const buffer = file?.buffer;
  const hasZipSignature =
    Buffer.isBuffer(buffer) &&
    buffer.length >= 4 &&
    buffer[0] === 0x50 &&
    buffer[1] === 0x4b &&
    (buffer[2] === 0x03 || buffer[2] === 0x05 || buffer[2] === 0x07) &&
    (buffer[3] === 0x04 || buffer[3] === 0x06 || buffer[3] === 0x08);

  return (
    ext === 'xlsx' ||
    ext === 'xlsm' ||
    mimetype === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    mimetype === 'application/vnd.ms-excel.sheet.macroenabled.12' ||
    hasZipSignature
  );
}

async function parseLeadUpload(file) {
  if (!file?.buffer) throw BadRequest('No file uploaded');
  const records = [];

  if (isCsvUpload(file)) {
    const lines = file.buffer
      .toString('utf8')
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    if (!lines.length) throw BadRequest('Uploaded file is empty');
    const first = splitCsvLine(lines[0]);
    const hasHeader = first.some((cell) => ['name', 'phone', 'mobile'].includes(cell.trim().toLowerCase()));
    const headers = hasHeader ? first : null;
    for (const line of hasHeader ? lines.slice(1) : lines) {
      records.push(rowToRecord(splitCsvLine(line), headers));
    }
  } else if (isOpenXmlExcelUpload(file)) {
    const workbook = new ExcelJS.Workbook();
    try {
      await workbook.xlsx.load(file.buffer);
    } catch (_err) {
      throw BadRequest('Could not read Excel file. Please upload a valid .xlsx file exported from Excel or Google Sheets.');
    }
    const sheet = workbook.worksheets[0];
    if (!sheet) throw BadRequest('Excel file has no sheets');
    const firstRow = sheet.getRow(1).values.slice(1).map(cellText);
    const hasHeader = firstRow.some((cell) => ['name', 'phone', 'mobile'].includes(cell.trim().toLowerCase()));
    const headers = hasHeader ? firstRow : null;
    const start = hasHeader ? 2 : 1;
    for (let rowNumber = start; rowNumber <= sheet.rowCount; rowNumber += 1) {
      const values = sheet.getRow(rowNumber).values.slice(1).map(cellText);
      if (values.every((value) => !value)) continue;
      records.push(rowToRecord(values, headers));
    }
  } else {
    throw BadRequest('Upload an Excel .xlsx/.xlsm or CSV .csv file');
  }

  const cleaned = records
    .map((record) => ({
      name: String(record.name || '').trim(),
      phone: String(record.phone || '').trim(),
      company: record.company ? String(record.company).trim() : null,
      email: record.email ? String(record.email).trim() : null,
      source: record.source ? String(record.source).trim() : null,
      notes: record.notes ? String(record.notes).trim() : null,
    }))
    .filter((record) => record.name && record.phone);

  if (!cleaned.length) {
    throw BadRequest('No valid leads found. Expected columns: name, phone, company, email, notes');
  }
  return cleaned;
}

function parseWorkingDays(value) {
  if (Array.isArray(value)) return value.map(Number);
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    if (Array.isArray(parsed)) return parsed.map(Number);
  } catch (_) {}
  return String(value).split(',').map((part) => Number(part.trim())).filter((part) => !Number.isNaN(part));
}

function assertExotelConfigured() {
  const missing = [];
  if (!config.exotel.sid) missing.push('EXOTEL_SID');
  if (!config.exotel.apiKey) missing.push('EXOTEL_API_KEY');
  if (!config.exotel.apiToken) missing.push('EXOTEL_API_TOKEN');
  if (!config.exotel.virtualNumber) missing.push('EXOTEL_VIRTUAL_NUMBER');
  if (missing.length) {
    throw BadRequest(`Exotel is not configured. Missing ${missing.join(', ')}`);
  }
}

async function listLeads({ user, q, status, ownerId, assignedDate, page = 1, pageSize = 25 }) {
  const assignedFor = assignedDate
    ? {
        gte: startOfUtcDay(assignedDate),
        lt: new Date(startOfUtcDay(assignedDate).getTime() + 24 * 60 * 60 * 1000),
      }
    : undefined;
  const where = tenant.tenantClause(user, {
    ...(status ? { status } : {}),
    ...(ownerId ? { ownerId } : {}),
    ...(assignedFor ? { assignedFor } : {}),
    ...(user.role === 'TELECALLER' ? { ownerId: user.id } : {}),
    ...(q
      ? {
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q } },
            { company: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {}),
  });
  const [total, items] = await prisma.$transaction([
    prisma.lead.count({ where }),
    prisma.lead.findMany({
      where,
      orderBy: [{ nextFollowAt: 'asc' }, { updatedAt: 'desc' }],
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: { owner: { select: { id: true, name: true, avatarUrl: true } } },
    }),
  ]);
  return { total, page, pageSize, items };
}

async function getLead(id, user) {
  const lead = await prisma.lead.findUnique({
    where: { id },
    include: {
      owner: { select: { id: true, name: true, avatarUrl: true } },
      calls: { orderBy: { createdAt: 'desc' }, take: 50 },
    },
  });
  if (!lead) throw NotFound('Lead not found');
  if (tenant.MULTI_TENANT && user) {
    tenant.assertSameTenant(user, lead.tenantId);
  }
  return lead;
}

async function createLead(input, creator) {
  const ownerId = input.ownerId || creator.id;
  const phone = normalizeLeadPhone(input.phone);
  if (!phone) {
    throw BadRequest(
      'Invalid phone number. Use formats like +917076119520, 07076119520, or 7076119520'
    );
  }
  if (input.ownerId && tenant.MULTI_TENANT) {
    const owner = await prisma.user.findUnique({
      where: { id: ownerId },
      select: { tenantId: true },
    });
    tenant.assertSameTenant(creator, owner?.tenantId);
  }
  return prisma.lead.create({
    data: {
      name: input.name,
      phone,
      company: input.company || null,
      email: input.email || null,
      status: input.status || 'NEW',
      ownerId,
      source: input.source || null,
      notes: input.notes || null,
      tags: input.tags || [],
      tenantId: tenant.userTenantId(creator),
      nextFollowAt: input.nextFollowAt ? new Date(input.nextFollowAt) : null,
      assignedFor: input.assignedFor ? startOfUtcDay(input.assignedFor) : null,
    },
  });
}

async function bulkDistributeLeads(input, creator) {
  const tenantId = tenant.userTenantId(creator);
  const telecallerIds = Array.from(new Set(input.telecallerIds || []));
  if (!telecallerIds.length) throw BadRequest('Select at least one telecaller');
  if (!input.records?.length) throw BadRequest('Add at least one customer record');

  const telecallers = await prisma.user.findMany({
    where: {
      id: { in: telecallerIds },
      role: 'TELECALLER',
      status: 'ACTIVE',
      ...(tenant.MULTI_TENANT ? { tenantId } : {}),
    },
    select: { id: true },
  });
  if (telecallers.length !== telecallerIds.length) {
    throw BadRequest('One or more selected users are not active telecallers');
  }

  const dates = workingDates({
    startDate: input.startDate,
    endDate: input.endDate,
    workingDays: input.workingDays,
  });
  if (!dates.length) throw BadRequest('No working days in the selected date range');

  const perTelecallerPerDay = Math.max(1, Math.min(Number(input.recordsPerTelecallerPerDay || 100), 500));
  const capacity = dates.length * telecallerIds.length * perTelecallerPerDay;
  const records = input.records.slice(0, capacity);
  if (!records.length) throw BadRequest('No records fit the selected distribution capacity');

  const data = [];
  let index = 0;
  for (const assignedFor of dates) {
    for (const ownerId of telecallerIds) {
      for (let count = 0; count < perTelecallerPerDay && index < records.length; count += 1) {
        const record = records[index];
        index += 1;
        data.push({
          name: record.name,
          phone: record.phone,
          company: record.company || null,
          email: record.email || null,
          source: record.source || input.source || 'bulk-distribution',
          notes: record.notes || null,
          status: 'NEW',
          ownerId,
          tenantId,
          assignedFor,
          tags: ['bulk-assigned'],
        });
      }
    }
  }

  await prisma.lead.createMany({ data, skipDuplicates: true });
  return {
    assigned: data.length,
    skipped: input.records.length - data.length,
    telecallers: telecallerIds.length,
    workingDays: dates.length,
    recordsPerTelecallerPerDay: perTelecallerPerDay,
  };
}

async function bulkDistributeLeadsFromFile({ file, input, creator }) {
  const records = await parseLeadUpload(file);
  const telecallerIds = Array.isArray(input.telecallerIds)
    ? input.telecallerIds
    : String(input.telecallerIds || '').split(',').map((id) => id.trim()).filter(Boolean);
  return bulkDistributeLeads({
    telecallerIds,
    startDate: input.startDate,
    endDate: input.endDate,
    recordsPerTelecallerPerDay: Number(input.recordsPerTelecallerPerDay || 100),
    workingDays: parseWorkingDays(input.workingDays),
    source: input.source,
    records,
  }, creator);
}

async function updateLead(id, input, user) {
  const lead = await getLead(id, user);
  if (user.role === 'TELECALLER' && lead.ownerId !== user.id) throw Forbidden();
  const data = { ...input };
  if (data.nextFollowAt) data.nextFollowAt = new Date(data.nextFollowAt);
  return prisma.lead.update({ where: { id }, data });
}

function assertTelecallerAgent(agent) {
  if (agent.role !== 'TELECALLER') {
    throw Forbidden('Only telecallers can place calls to leads');
  }
}

async function clickToCall({ leadId, agent }) {
  assertTelecallerAgent(agent);
  const lead = await getLead(leadId, agent);
  if (!lead.phone) throw BadRequest('Lead has no phone number');
  if (!agent.phone) throw BadRequest('Add your calling phone number in Profile before making telecaller calls');
  assertExotelConfigured();

  const fromNumber = normalizePhoneNumber(agent.phone);
  const toNumber = normalizePhoneNumber(lead.phone);
  if (!fromNumber) throw BadRequest('Your calling phone number is invalid');
  if (!toNumber) throw BadRequest('Lead phone number is invalid');

  const result = await exotel.connectCall({
    from: fromNumber,
    to: toNumber,
    callerId: config.exotel.virtualNumber,
    statusCallback: config.exotel.callbackUrl,
  });

  const call = await prisma.telecallerCall.create({
    data: {
      leadId,
      agentId: agent.id,
      direction: 'OUTBOUND',
      externalCallId: result.Sid || result.sid || null,
      fromNumber,
      toNumber,
      status: result.Status || result.status || 'queued',
    },
  });

  await prisma.lead.update({
    where: { id: leadId },
    data: { status: lead.status === 'NEW' ? 'CONTACTED' : lead.status },
  });

  return { call, exotel: result };
}

async function logPhoneDial({ leadId, agent }) {
  assertTelecallerAgent(agent);
  const lead = await getLead(leadId, agent);
  if (!lead.phone) throw BadRequest('Lead has no phone number');
  if (!agent.phone) throw BadRequest('Add your calling phone number in Profile before making telecaller calls');

  const fromNumber = normalizePhoneNumber(agent.phone);
  const toNumber = normalizePhoneNumber(lead.phone);
  if (!fromNumber) throw BadRequest('Your calling phone number is invalid');
  if (!toNumber) throw BadRequest('Lead phone number is invalid');

  const call = await prisma.telecallerCall.create({
    data: {
      leadId,
      agentId: agent.id,
      direction: 'OUTBOUND',
      fromNumber,
      toNumber,
      status: 'dialer_opened',
    },
  });

  await prisma.lead.update({
    where: { id: leadId },
    data: { status: lead.status === 'NEW' ? 'CONTACTED' : lead.status },
  });

  return { call, phone: { to: toNumber } };
}

async function updateCallOutcome(callId, input, user) {
  const outcome = String(input.outcome || '').trim().toUpperCase();
  if (!CALL_OUTCOMES.has(outcome)) throw BadRequest('Invalid call outcome');

  const call = await prisma.telecallerCall.findUnique({
    where: { id: callId },
    include: { lead: true, agent: { select: { id: true, tenantId: true } } },
  });
  if (!call) throw NotFound('Call not found');
  if (user.role === 'TELECALLER' && call.agentId !== user.id) throw Forbidden();
  if (tenant.MULTI_TENANT && user.role !== 'TELECALLER') {
    tenant.assertSameTenant(user, call.agent?.tenantId);
  }

  const updated = await prisma.$transaction(async (tx) => {
    const saved = await tx.telecallerCall.update({
      where: { id: callId },
      data: {
        status: outcome,
        notes: input.notes || null,
        endedAt: new Date(),
      },
      include: {
        lead: { select: { id: true, name: true, phone: true, status: true } },
        agent: { select: { id: true, name: true } },
      },
    });

    if (call.lead) {
      await tx.lead.update({
        where: { id: call.lead.id },
        data: { status: leadStatusForOutcome(outcome, call.lead.status) },
      });
    }
    return saved;
  });

  return updated;
}

async function handleWebhook(payload) {
  const sid = payload.CallSid || payload.sid;
  if (!sid) return null;
  return prisma.telecallerCall.updateMany({
    where: { externalCallId: sid },
    data: {
      status: payload.Status || payload.status,
      durationSec: payload.Duration ? parseInt(payload.Duration, 10) : undefined,
      recordingUrl: payload.RecordingUrl || undefined,
      startedAt: payload.StartTime ? new Date(payload.StartTime) : undefined,
      endedAt: payload.EndTime ? new Date(payload.EndTime) : undefined,
    },
  });
}

async function callHistory({ user, page = 1, pageSize = 50 }) {
  const where = user.role === 'TELECALLER'
    ? { agentId: user.id }
    : tenant.isPlatformSuperAdmin(user)
      ? {}
      : { agent: { tenantId: tenant.userTenantId(user) } };
  const [total, items] = await prisma.$transaction([
    prisma.telecallerCall.count({ where }),
    prisma.telecallerCall.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: {
        lead: { select: { id: true, name: true, company: true } },
        agent: { select: { id: true, name: true } },
      },
    }),
  ]);
  return { total, page, pageSize, items };
}

async function followupsDueToday(user) {
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(); end.setHours(23, 59, 59, 999);
  return prisma.lead.findMany({
    where: tenant.tenantClause(user, {
      ...(user.role === 'TELECALLER' ? { ownerId: user.id } : {}),
      nextFollowAt: { gte: start, lte: end },
    }),
    orderBy: { nextFollowAt: 'asc' },
  });
}

async function attachCallRecording(callId, input, user) {
  const call = await prisma.telecallerCall.findUnique({
    where: { id: callId },
    include: { agent: { select: { id: true, tenantId: true } } },
  });
  if (!call) throw NotFound('Call not found');
  if (user.role === 'TELECALLER' && call.agentId !== user.id) throw Forbidden();
  if (tenant.MULTI_TENANT && user.role !== 'TELECALLER') {
    tenant.assertSameTenant(user, call.agent?.tenantId);
  }

  let url = input.url || null;
  if (!url && input.fileId) {
    const file = await prisma.fileAsset.findUnique({ where: { id: input.fileId } });
    url = file?.url || null;
  }
  if (!url) throw BadRequest('Recording url required');

  return prisma.telecallerCall.update({
    where: { id: callId },
    data: { recordingUrl: url },
  });
}

module.exports = {
  listLeads,
  getLead,
  createLead,
  bulkDistributeLeads,
  bulkDistributeLeadsFromFile,
  updateLead,
  clickToCall,
  logPhoneDial,
  updateCallOutcome,
  attachCallRecording,
  handleWebhook,
  callHistory,
  followupsDueToday,
};
