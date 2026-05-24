'use strict';

const prisma = require('../../database/prisma');

/**
 * Postgres-backed search adapter — case-insensitive contains + a small
 * recent-activity boost.
 *
 * Supports inline filter syntax in the query string, parsed out before the
 * Postgres LIKE so users can scope a search:
 *
 *   from:priya     → messages whose author name / userId / email matches
 *   in:#design     → messages within a channel whose name matches
 *   type:pdf       → files whose mime/originalName/category contains "pdf"
 *
 * Each filter consumes only the matching token; remaining words become the
 * free-text term. An empty free-text term is allowed when filters are present
 * (e.g. "from:priya" returns every recent message from Priya).
 */

const FILTER_RE = /(\w+):("([^"]+)"|(\S+))/g;
const FILTER_KEYS = new Set(['from', 'in', 'type']);

function parseQuery(raw) {
  const filters = { from: null, in: null, type: null };
  let term = raw;
  term = term.replace(FILTER_RE, (match, key, _quoted, quoted, unquoted) => {
    const k = key.toLowerCase();
    if (!FILTER_KEYS.has(k)) return match;
    const value = (quoted || unquoted || '').replace(/^#/, '');
    if (value) filters[k] = value;
    return '';
  });
  return { term: term.replace(/\s+/g, ' ').trim(), filters };
}

async function search({ user, q, kinds, perEntity = 6, recentBoost = true }) {
  const isClient = user.isClient;
  const isAdmin = ['SUPER_ADMIN', 'ADMIN'].includes(user.role);
  const wants = (k) => !kinds || kinds.includes(k);
  const { term, filters } = parseQuery(q);

  const myChannelIds = await prisma.channelMember
    .findMany({ where: { userId: user.id }, select: { channelId: true } })
    .then((rows) => rows.map((r) => r.channelId));

  // Resolve filters to concrete IDs once so each parallel search reuses them.
  let fromUserIds = null;
  if (filters.from) {
    const matches = await prisma.user.findMany({
      where: {
        OR: [
          { userId: { contains: filters.from, mode: 'insensitive' } },
          { name:   { contains: filters.from, mode: 'insensitive' } },
          { email:  { contains: filters.from, mode: 'insensitive' } },
        ],
      },
      take: 10,
      select: { id: true },
    });
    fromUserIds = matches.map((m) => m.id);
    // If `from:` matches nobody, return early — every kind would be empty anyway.
    if (fromUserIds.length === 0) return { results: {}, term, filters };
  }

  let inChannelIds = null;
  if (filters.in) {
    const matches = await prisma.channel.findMany({
      where: {
        ...(isAdmin ? {} : { id: { in: myChannelIds } }),
        name: { contains: filters.in, mode: 'insensitive' },
      },
      take: 10,
      select: { id: true },
    });
    inChannelIds = matches.map((m) => m.id);
    if (inChannelIds.length === 0) return { results: {}, term, filters };
  }

  // For free-text we need at least 1 char to avoid scanning everything,
  // unless filters narrow the scope (then any/empty term is OK).
  const hasFilters = !!(filters.from || filters.in || filters.type);
  if (!term && !hasFilters) return { results: {}, term, filters };

  // "contains" condition reused everywhere; null when we only have filters.
  const containsTerm = term
    ? { contains: term, mode: 'insensitive' }
    : null;
  const containsTermNoMode = term ? { contains: term } : null;

  const tasks = [];

  // ----- people -----
  if (wants('users') && !isClient) {
    // When `from:` is set, the user already filtered to a specific person —
    // skip the people category in that case so results focus on messages/files.
    if (!filters.from) {
      tasks.push(
        prisma.user
          .findMany({
            where: containsTerm
              ? {
                  OR: [
                    { userId: containsTerm },
                    { name:   containsTerm },
                    { email:  containsTerm },
                  ],
                }
              : {},
            orderBy: recentBoost ? { lastSeenAt: 'desc' } : { createdAt: 'desc' },
            take: perEntity,
            select: {
              id: true, userId: true, name: true, role: true, isClient: true,
              avatarUrl: true, clientCompany: true, customTitle: true,
              lastSeenAt: true,
            },
          })
          .then((items) => ['users', items])
      );
    }
  }

  // ----- channels -----
  if (wants('channels')) {
    tasks.push(
      prisma.channel
        .findMany({
          where: {
            archived: false,
            ...(isAdmin ? {} : { id: { in: myChannelIds } }),
            ...(inChannelIds ? { id: { in: inChannelIds } } : {}),
            ...(containsTerm
              ? { OR: [{ name: containsTerm }, { description: containsTerm }] }
              : {}),
          },
          orderBy: recentBoost ? { updatedAt: 'desc' } : { createdAt: 'desc' },
          take: perEntity,
          select: {
            id: true, name: true, kind: true, isClientChannel: true,
            description: true, updatedAt: true,
          },
        })
        .then((items) => ['channels', items])
    );
  }

  // ----- tasks -----
  if (wants('tasks') && !filters.from && !filters.in) {
    tasks.push(
      prisma.task
        .findMany({
          where: {
            ...(containsTerm
              ? { OR: [{ title: containsTerm }, { description: containsTerm }] }
              : {}),
            ...(!isAdmin
              ? {
                  OR: [
                    { createdById: user.id },
                    { assignees: { some: { userId: user.id } } },
                  ],
                }
              : {}),
          },
          orderBy: { updatedAt: 'desc' },
          take: perEntity,
          select: {
            id: true, title: true, status: true, priority: true,
            dueAt: true, updatedAt: true,
          },
        })
        .then((items) => ['tasks', items])
    );
  }

  // ----- messages (with author + channel + attachment indicator) -----
  if (wants('messages')) {
    const channelScope = inChannelIds
      ? { in: inChannelIds }
      : (isAdmin ? undefined : { in: myChannelIds });

    tasks.push(
      prisma.message
        .findMany({
          where: {
            deletedAt: null,
            ...(containsTerm ? { body: containsTerm } : {}),
            ...(channelScope ? { channelId: channelScope } : {}),
            ...(fromUserIds ? { authorId: { in: fromUserIds } } : {}),
          },
          orderBy: { createdAt: 'desc' },
          take: perEntity,
          select: {
            id: true, body: true, kind: true, createdAt: true, channelId: true,
            author: {
              select: { id: true, name: true, avatarUrl: true, isClient: true, role: true, userId: true },
            },
            channel: {
              select: { id: true, name: true, kind: true, isClientChannel: true },
            },
            attachments: {
              take: 3,
              select: {
                id: true, originalName: true, mimeType: true, size: true,
                url: true, previewUrl: true,
              },
            },
          },
        })
        .then((items) => ['messages', items])
    );
  }

  // ----- files (with uploader info + optional type filter) -----
  if (wants('files')) {
    const typeFilter = filters.type
      ? {
          OR: [
            { mimeType:     { contains: filters.type, mode: 'insensitive' } },
            { originalName: { contains: filters.type, mode: 'insensitive' } },
            { category:     { contains: filters.type, mode: 'insensitive' } },
          ],
        }
      : null;

    const textFilter = containsTerm
      ? {
          OR: [
            { originalName: containsTerm },
            { category:     containsTerm },
            { mimeType:     containsTerm },
          ],
        }
      : null;

    // Non-admins see files they uploaded OR files attached to messages in
    // channels they belong to.
    const visibility = isAdmin
      ? null
      : {
          OR: [
            { uploadedById: user.id },
            { messages: { some: { channelId: { in: myChannelIds } } } },
          ],
        };

    tasks.push(
      prisma.fileAsset
        .findMany({
          where: {
            AND: [
              textFilter || {},
              typeFilter || {},
              visibility || {},
              fromUserIds ? { uploadedById: { in: fromUserIds } } : {},
            ].filter((c) => Object.keys(c).length > 0),
          },
          orderBy: { createdAt: 'desc' },
          take: perEntity,
          select: {
            id: true, url: true, previewUrl: true, originalName: true,
            mimeType: true, size: true, backend: true, category: true,
            createdAt: true,
            uploadedBy: { select: { id: true, name: true, isClient: true, avatarUrl: true } },
            messages: {
              take: 1,
              orderBy: { createdAt: 'desc' },
              select: {
                id: true, channelId: true,
                channel: { select: { id: true, name: true, isClientChannel: true } },
              },
            },
          },
        })
        .then((items) => ['files', items])
    );
  }

  // ----- leads -----
  if (wants('leads') && !isClient && !filters.from && !filters.in && !filters.type) {
    tasks.push(
      prisma.lead
        .findMany({
          where: {
            ...(user.role === 'TELECALLER' ? { ownerId: user.id } : {}),
            ...(containsTerm
              ? {
                  OR: [
                    { name:    containsTerm },
                    { phone:   containsTermNoMode },
                    { company: containsTerm },
                  ],
                }
              : {}),
          },
          orderBy: { updatedAt: 'desc' },
          take: perEntity,
          select: { id: true, name: true, phone: true, company: true, status: true },
        })
        .then((items) => ['leads', items])
    );
  }

  const settled = await Promise.all(tasks);
  return { results: Object.fromEntries(settled), term, filters };
}

async function index() { /* postgres adapter — nothing to do, we query live */ }
async function deindex() { /* postgres adapter — nothing to do, we query live */ }

module.exports = { search, index, deindex };
