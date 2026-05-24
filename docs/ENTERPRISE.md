# MyTaskKing — Enterprise Architecture

Reference for the platform's enterprise-grade features: multi-tenancy, advanced RBAC, sessions, audit, analytics, automations, and the AI roadmap.

---

## 1. Multi-tenancy

**Status today:** every record lives in a single synthetic `Tenant` row (`default`). The schema is multi-tenant-ready; the runtime can flip into multi-tenant mode with one env var.

**Flag:** `MULTI_TENANT=true`. When off, `req.tenantId` is `null` and `scopedWhere` is a no-op.

**Schema commitment:**
- `Tenant(id, slug, name, branding, storagePrefix, …)`
- `tenantId` is added to the top-level entities (`User`, `Channel`, `Task`, `Lead`, `FileAsset`). Nullable today, becomes non-null after the migration below.

**Migration path** (when going multi-tenant):

1. Create one `Tenant` row per existing company.
2. Backfill `tenantId` on all top-level rows.
3. Add `NOT NULL` constraints in a follow-up migration.
4. Toggle `MULTI_TENANT=true`. From that point on:
   - `services/tenant.js#scopedWhere(req, where)` injects `{ tenantId: req.tenantId }` into every Prisma query.
   - `services/tenant.js#withTenant(req, data)` stamps `tenantId` on creates.
   - The JWT-encoded user's `tenantId` becomes the source of truth.

**Storage isolation:** `Tenant.storagePrefix` becomes a folder prefix on Cloudinary + R2 uploads. The upload paths today are flat (`bestie/chat`, `files/...`); flip them to `${storagePrefix}/...` in `services/cloudinary.js` and `services/r2.js`.

**Sub-domains:** `<tenant.slug>.mytaskking.app` resolves via Cloudflare. Add the host parser middleware (`resolveTenantFromHost`) in front of `attachTenant` to support sub-domain login.

---

## 2. Advanced RBAC

Layered model so legacy `Role` keeps working while the new permission grants extend it.

**Resolution order:**
1. Explicit deny grant on the user.
2. Explicit allow grant on the user.
3. Deny grant on the role.
4. Allow grant on the role.
5. Baked-in role defaults (`DEFAULT_MATRIX` in `services/rbac.js`).

**Permission keys** are dot-namespaced strings. Adding a new key never requires a migration — just call `can(user, 'new.key')` from your route. Patterns supported in grants:
- exact: `task.delete`
- wildcard: `task.*`
- universal: `*`

**Module-level keys** (subset):

| Module | Keys |
|---|---|
| Audit | `audit.view` |
| Analytics | `analytics.view` |
| Channels | `channel.read`, `channel.post`, `channel.invite`, `channel.manage`, `channel.delete` |
| Tasks | `task.read`, `task.create`, `task.update`, `task.delete`, `task.assign_self`, `task.assign_others` |
| Calls | `call.read`, `call.create`, `call.record`, `call.transfer` |
| Files | `file.upload`, `file.read`, `file.view_client`, `file.share_external` |
| Settings | `settings.write` |
| Sessions | `session.force_logout` |
| Permissions | `permission.write` |
| Announcements | `announcement.publish` |

**Frontend hint:** `GET /permissions/mine` returns `{ defaults, grants }` so the UI can hide buttons. Don't rely on this for security — server-side `requirePerm()` is authoritative.

---

## 3. Sessions

Every successful login creates a `Session` row linked to the `RefreshToken` row. Logout / refresh-rotate / force-logout flip its status.

**Risk scoring:** simple heuristic in `services/sessions.js#startSession`. New IP or new device adds 20–30 points; `riskScore >= 30` shows the "Risk" badge in the UI. A real implementation should plug into a fraud signal provider — the score is the only thing the UI cares about, so swap the input without breaking anything else.

**Admin override:** `POST /sessions/users/:userId/force-logout` revokes every active session for a user and flips their refresh tokens. The user gets `401` on their next request, lands on `/login`.

---

## 4. Audit log

Same kind-namespace as before, now richer:
- `auth.login`, `auth.login_failed`, `auth.logout`
- `session.revoked`, `session.force_logout`
- `permission.granted`, `permission.revoked`, `permission.changed`
- `file.policy_changed`, `file.granted`, `file.downloaded`
- `automation.created`, `automation.ran`
- `announcement.published`

All emit `activity.recorded` over Socket.IO so the Activity page and the NotificationCenter stay live.

---

## 5. Presence

Two layers:

- **Realtime** — the Socket.IO presence map (`backend/src/sockets/index.js`) tracks "is currently connected" and broadcasts `presence.update`. Authoritative for "online now."
- **Status** — `UserPresence` table holds `ACTIVE | AWAY | BUSY | IN_MEETING | INVISIBLE` + optional `customStatus`. Authoritative for "what the user told us they're doing."

Combine both on the frontend: a user is "online + busy" when there's a socket + status=BUSY. The `<PresenceDot />` component handles all six states (the sixth is `OFFLINE` — derived when no socket and no recent `lastSeenAt`).

Cross-channel typing now carries `threadRootId` so the thread side-panel shows typing indicators independently from the main channel.

---

## 6. Message threading

Schema is fully denormalized for fast access:
- `Message.replyToId` — pointer to the immediate parent (any nesting level).
- `Message.threadRootId` — denormalized pointer to the top-of-thread message.
- `Message.threadReplyCount`, `Message.threadLastReplyAt` — counters for fast list rendering.

When a message is sent with `replyToId`, the server resolves `threadRootId` from the parent's existing root (or uses the parent itself if it's not yet threaded). The root counters update asynchronously — never block the send.

**API:**
- `POST /chat/channels/:channelId/messages` accepts `replyToId` and optional `threadRootId`.
- `GET /chat/threads/:rootId` returns `{ root, replies }`.
- Socket: `chat.thread.reply` event fires alongside `chat.message.created` for thread participants.

---

## 7. File permissions

`FileAccessPolicy` controls visibility:

| visibility | who can access |
|---|---|
| `PRIVATE` | uploader + explicit `FileGrant` rows |
| `CHANNEL` | members of the policy's `channelId` |
| `TENANT` | any user in the same tenant |
| `PUBLIC` | anyone with the link (rare) |

Centralized in `services/fileAccess.js#canAccess` so download URLs, previews, version history, and policy reads all enforce the same rules. Every download is logged in `FileDownload` and emits a `file.downloaded` audit event.

Expiring URLs come from the existing R2 presigned-URL flow (15 min); `FileGrant.expiresAt` adds a per-user time-bound override on top.

---

## 8. Task automations

Two evaluation paths:

- **Scheduled** (`RECURRING_SCHEDULE`) — one `node-cron` task per automation, registered at boot via `automations.registerSchedules()` and re-registered on create/update/delete.
- **Event-triggered** — `runEventTriggered({ trigger, context })` called inline from `task.create` and `task.move`. `TASK_OVERDUE` runs via a 5-minute sweep so it doesn't depend on someone hitting an endpoint.

**Triggers × actions** form a 6 × 6 matrix — only the meaningful combinations are wired (e.g. `TASK_OVERDUE → NOTIFY_MANAGER`, `RECURRING_SCHEDULE → CREATE_TASK`, `LEAD_STATUS_CHANGED → NOTIFY_USER`). The dispatcher is tiny on purpose; complex flows should be composed of multiple automations rather than one giant one.

---

## 9. Search adapter

`services/searchAdapter.js` is the only call site outside the search module. Today it routes to `searchAdapters/postgres.js`. To upgrade:

1. Implement `searchAdapters/meilisearch.js` exporting `{ search, index, deindex }`.
2. Set `SEARCH_ENGINE=meilisearch` and provide whatever credentials the adapter needs.
3. Hook `adapter.index({ entity, id, doc })` into the create/update sites of `Message`, `Task`, `Lead`, `FileAsset`, `Channel`, `User`.
4. The route signature doesn't change — both engines must implement the same `{ user, q, kinds, perEntity, recentBoost }` contract.

---

## 10. Analytics

Centralized under `/analytics/*`. Admin-only. Returns raw aggregations — the UI does its own charting (web today, future Flutter desktop dashboards too). Each endpoint takes `?from&to` (defaults to last 30 days).

| Endpoint | Returns |
|---|---|
| `productivity` | tasks completed per user |
| `telecaller` | calls/minute/leads-won per agent |
| `tasks` | by-status counts + overdue gauge |
| `workspace` | messages, active users, calls |
| `client-engagement` | message counts per client |
| `calls` | by-status counts |

For exports, the same query parameters drive CSV by adding `?format=csv` — implement in the route by piping through `fast-csv`.

---

## 11. OpenAPI

- Spec: `backend/src/modules/openapi/openapi.json`
- Reference UI: `/api/v1/docs` (Swagger UI loaded from CDN)
- Machine-readable: `/api/v1/openapi.json`

We curate by hand. The spec is the API contract — when adding a route, add the path + minimal schema. Auto-generation tools tend to drift from reality on Node/Express projects; curated specs stay accurate.

---

## 12. Standardized response envelope

Legacy routes return raw payloads. New routes can opt into `res.success(data)` / `res.fail(status, code, msg)` which wraps:

```json
{ "ok": true, "data": {…}, "meta": {…}, "traceId": "abc123" }
{ "ok": false, "error": { "code": "...", "message": "...", "traceId": "abc123" } }
```

Every response carries `X-Trace-Id`. New module recipe: start with the envelope.

---

## 13. AI roadmap

Reaffirmed: `services/ai.js` is the only place that knows what provider is in use. Today it's a no-op. Plugging in `anthropic` or `openai`:

| Capability | Hook | UX surface |
|---|---|---|
| Task summary | `task.service.js#getById` → `ai.summarize({ kind: 'task' })` | A `Summarize` action in the task panel |
| Meeting summary | `calls/service` end-of-call → `ai.transcribe` then `ai.summarize` | Posts a system message into the call's channel |
| Smart search | `searchAdapter` wrapper | Top-N hits reranked before response |
| Realtime translation | new socket event `chat.translate` → `ai.translate` (add to ai.js) | Inline button under foreign-language messages |
| AI task generation | `automation.action = "AI_SUGGEST_TASKS"` (new) → posts proposals into a channel | Admin reviews proposals before they spawn |
| Weekly insights | `analytics` cron → `ai.insights` → cached on `WorkspaceSetting` | New widget on admin dashboard |

The rule is unchanged: never block user-facing operations on AI. All paths must degrade gracefully when `AI_PROVIDER=noop`.

---

## 14. Future-proofing checklist

When adding a new module, this is the contract:

- Service in `backend/src/modules/<name>/<name>.service.js` — pure functions on Prisma.
- Routes in `<name>.routes.js` — `requireAuth` + `requireRole` or `requirePerm`, Joi-validated, audit-recorded.
- Register in `backend/src/modules/index.js`.
- Add OpenAPI entries.
- Add the page under `frontend/react_web/src/pages/`.
- Hook the nav into `WorkspaceLayout.tsx` with role-allowlist.
- Tenant-aware: pass through `scopedWhere`/`withTenant`.
- AI-aware: any heuristic should have an `ai.*` opt-in path.

If you do all eight, the module slots in without touching anything else.
