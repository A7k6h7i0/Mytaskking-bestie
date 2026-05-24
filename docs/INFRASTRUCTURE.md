# MyTaskKing — Infrastructure

Operational reference for the ultra-enterprise layer: event bus, cache, queues, distributed sockets, media pipeline, video, observability, security, CI/CD, feature flags, customization, and realtime collaboration.

---

## 1. Event bus

[`services/eventBus.js`](../backend/src/services/eventBus.js) provides the only inter-module communication channel modules should use.

- **Today's transport:** in-process `EventEmitter` + a Postgres-backed `OutboxEvent` table.
- **Adapter slot:** `EVENT_TRANSPORT=kafka|rabbitmq|sqs` selects an external dispatcher (implementations live in `services/eventTransports/<name>.js` — not bundled yet; the slot is reserved).
- **Outbox guarantees:** events written inside a Prisma transaction are durable. The dispatcher (started in `app.js`) drains pending rows every 2 s with exponential backoff and a 10-attempt cap before marking `FAILED`.

**Producer pattern:**

```js
await prisma.$transaction(async (tx) => {
  const task = await tx.task.create({...});
  await eventBus.publish('task.created', { id: task.id }, { tx });
});
```

**Consumer pattern (anywhere in the codebase):**

```js
eventBus.subscribe('task.*', async (event) => { /* ... */ });
```

Handlers run async — never block producers. Failures are caught and logged with the topic.

---

## 2. Cache

[`services/cache.js`](../backend/src/services/cache.js) is the one cache abstraction.

- If `REDIS_URL` is set, uses `ioredis`. Otherwise drops to an in-memory Map with TTL.
- Used by: session lookups (planned), brute-force counters, presence flags, feature-flag resolution, memoized hot reads via `repository.cachedFindUnique`.
- Same connection is reused by BullMQ (queues) and the Socket.IO Redis adapter — no extra Redis connection pool.

**API:** `get/set/del/incr/memoize`. `cache.mode` reports `"redis"` or `"memory"` at boot.

---

## 3. Queues

[`services/queue.js`](../backend/src/services/queue.js) — single API, two drivers:

| `QUEUE_DRIVER` | Behavior |
|---|---|
| `memory` | In-process queue, no durability across restarts. Good for dev / single instance. |
| `bullmq` | BullMQ on Redis with retries, DLQ, worker scaling, metrics. Requires `REDIS_URL`. |

The API process registers queue handlers only when running in memory mode. For BullMQ, run `node src/worker.js` as a separate process (PM2 entry `bestie-worker`). The worker shares all module code with the API — same Prisma client, same services.

---

## 4. Distributed Socket.IO

When `REDIS_URL` is configured, [`sockets/index.js`](../backend/src/sockets/index.js) attaches `@socket.io/redis-adapter`. All `io.emit` / `io.to(room).emit` fan out across every API instance behind the load balancer.

Presence is double-tracked: in-process Map for fast lookups + a Redis key (`presence:online:<userId>`) so any instance can answer "is this user online?" without bouncing via socket queries.

---

## 5. Media pipeline

Upload hot path stays fast: persist the `FileAsset`, then enqueue a `MediaJob` for compression / thumbnail / preview / transcode. The worker (or the API process in dev) drains them through [`services/media.js`](../backend/src/services/media.js).

Job kinds today (handlers are stubs that mark jobs `DONE`; wire concrete processors when the workload arrives):

- `IMAGE_COMPRESS` — sharp / Cloudinary eager
- `IMAGE_THUMBNAIL` — Cloudinary URL transform writes `previewUrl`
- `PDF_PREVIEW` — page-1 render
- `AUDIO_OPTIMIZE`, `VIDEO_TRANSCODE` — ffmpeg
- `CHUNK_REASSEMBLY` — reassemble client-side chunked uploads into a single R2 object

The `MediaJob` row keeps `attempts`, `error`, timestamps. Failed jobs are kept (not deleted) so admins can replay.

---

## 6. Video-ready calling

`MeetingRoom(slug, name, mode, channelName, …)` adds a first-class room concept on top of the Agora channel-name primitive. `mode` ∈ `VOICE | VIDEO | WEBINAR | LIVESTREAM`. The token endpoint is identical for all modes — the Agora SDK on the client decides whether to publish audio-only, audio+video, or large-room mode. Recordings populate `recordingUrl` via Agora Cloud Recording webhooks (wire when enabling).

Routes: `GET/POST /meetings`, `POST /meetings/:slug/token`, `POST /meetings/:slug/end`. Socket events stay reused: `call.signal`, `call.participant.*`, plus the new `call.screen_share.*` from the previous layer.

---

## 7. Repository pattern & read replicas

[`database/repository.js`](../backend/src/database/repository.js) exposes:

- `repo.writer` — always the primary
- `repo.reader` — primary, or a separate `PrismaClient` pointed at `READ_REPLICA_URL` when set
- `repo.tx(fn)` — transaction on the writer
- `repo.cachedFindUnique(model, where, { ttl })` — cached single-row reads

Migration plan: existing modules keep using `database/prisma` directly. As you hit hot reads (auth middleware loading the user on every request, channel list on every chat open), swap them to `repo.reader.*` and watch latency drop.

---

## 8. Observability

- **Correlation IDs:** [`middleware/correlationId.js`](../backend/src/middleware/correlationId.js) mints / honors `X-Trace-Id` and stores `{ traceId, userId, tenantId }` in `AsyncLocalStorage`. The Pino logger reads from ALS via its `mixin` so every log line carries trace context.
- **Metrics:** `/metrics` Prometheus endpoint with HTTP counts, durations, socket gauge, plus per-path stats.
- **Sentry:** opt-in via `SENTRY_DSN`. Request + error handlers pre-installed.
- **OpenTelemetry slot:** swap the `randomBytes` trace-id mint for `trace.getActiveSpan()?.spanContext().traceId` and the rest of the pipeline (ALS, logger mixin, response header) carries through unchanged.
- **Loki / Grafana / Prometheus:** Pino's JSON output ships cleanly to Loki via Promtail. Prometheus scrapes `/metrics`. No code changes — pure ops wiring.

---

## 9. Security hardening

[`middleware/security.js`](../backend/src/middleware/security.js):

- **CSP** — deny by default, allowlisted for Cloudinary / R2 / Google Fonts / Swagger UI on unpkg.
- **HSTS** — 1-year, `includeSubDomains`, `preload`.
- **Brute-force** — `bruteForce({ key, threshold, window, block })` middleware backed by the cache service. Counts per (ip, userId) and short-circuits with `429` while blocked.
- **Suspicious activity** — `flagSuspicious(req, reason)` for heuristic hits.
- **Field encryption** — AES-256-GCM helpers (`encrypt`/`decrypt`). Reads the key from `FIELD_ENCRYPTION_KEY`; throws if unset. Use for any column that stores sensitive data the DB shouldn't carry in plaintext.
- **Refresh-token rotation** — already implemented; the prior layer added Session bookkeeping + force-logout. Combine with `TrustedDevice` (new schema) to extend long-lived trust to specific devices.

---

## 10. Feature flags

`FeatureFlag` (definition) + `FeatureFlagAssignment` (per-user overrides). Rollouts: `GLOBAL | ROLE | USER | TENANT | PERCENT`. Resolution is cached per `(key, userId)` for 30 s through the shared cache, so a flip propagates inside half a minute even at scale.

- Admin API: `PUT /flags/:key`, `POST /flags/:key/assign`.
- User API: `GET /flags/mine` returns the full resolved map.
- React hook: `useFeatureFlag('ai.task_summary')` → `{ enabled, payload }`.

**Rule:** flags are UI affordances, not security boundaries. Server-side RBAC + per-route checks remain authoritative.

---

## 11. Workspace customization

- **Themes** — `WorkspaceTheme(name, mode, tokens, isDefault)` rows; the frontend looks up the default per tenant and merges into CSS custom properties. The shipped `ThemeSwitcher` handles `light | dark | system` for the user, with `system` honoring `prefers-color-scheme`.
- **Dashboard widgets** — `DashboardWidget(kind, config, position, visible)` per-user. `PUT /workspace/widgets` accepts the full ordered set; replace-the-set semantics. Frontend will render whatever the user has configured; default widget list ships in the next pass.

---

## 12. Realtime collaboration prep

[`services/collab.ts`](../frontend/react_web/src/services/collab.ts) wraps the Socket.IO connection in a yjs-shaped API:

```ts
const room = joinCollabRoom('task:abc');
room.onPresence((peers) => …);
room.publishCursor({ x, y });
room.publishOp(op);
```

The server side relays cursors and opaque ops to the room. Swapping in yjs later replaces this transport without changing call sites: `joinCollabRoom` would return a `Y.Doc` wrapped in the same interface, the yjs provider handles delivery, and the manual cursor/op relays delete cleanly.

---

## 13. DevOps & CI/CD

- **CI** ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) — Postgres + Redis services, Prisma migrate, syntax check, web build, Flutter analyze for shared packages.
- **Deploy** ([`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)) — environment-scoped, rsync over SSH, Prisma migrate deploy, PM2 reload, readiness smoke check. Refuses to proceed on migration drift.
- **Rollback** ([`deploy/rollback.sh`](../deploy/rollback.sh)) — checkout a previous ref into a parallel directory, swap PM2's symlink, validate migrations don't drift. Refuses to roll back across destructive migrations — forward-fix instead.
- **Backups** — `deploy/backup.sh` runs nightly, ships to R2 when configured, prunes after `RETENTION_DAYS`.

Required GitHub secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`, `DEPLOY_SSH_KEY`, `DATABASE_URL`, `PUBLIC_API_URL`, `PUBLIC_API_URL_HOST`.

---

## 14. Health endpoints

| Path | Purpose |
|---|---|
| `/health` | liveness — process is up |
| `/health/live` | k8s-style liveness probe |
| `/health/ready` | k8s-style readiness — pings DB + reports cache mode |
| `/metrics` | Prometheus |
| `/api/v1/docs` | Swagger UI |
| `/api/v1/openapi.json` | machine-readable spec |

---

## 15. Mobile experience hooks

Flutter clients ([`flutter_apps/shared_core`](../frontend/flutter_apps/shared_core/lib/bestie_core.dart)) already carry secure-storage-backed auth + Dio API + Socket.IO. Extension points:

- **Background sync** — add `workmanager` or `flutter_background_service`; replay the outbox table on each tick.
- **Offline queue** — implement on top of `drift` / `sqflite` per the offline blueprint in `docs/EXTENSIONS.md`.
- **Push deep-link handling** — FCM payload always carries `data.kind` + the referenced entity id; the mobile app routes accordingly. The web SW will follow.
- **Adaptive layouts** — desktop targets render the `BestieSidebar` widget directly; the mobile shell uses the bottom-navigation home screen.

---

## 16. The two configurations

For clarity, here's what the platform looks like in each mode:

**Single-instance, no Redis** — what you get with `npm run dev`. In-process cache, in-memory queue, no socket clustering, in-process event bus. Fine for staging, small deployments. The API also runs the worker.

**Clustered, Redis + BullMQ + replica + Sentry** — production target. Multiple API instances behind a load balancer share state through Redis. `bestie-worker` runs as PM2 entries on every box. `READ_REPLICA_URL` siphons read traffic. `SENTRY_DSN` captures exceptions. `MULTI_TENANT=true` once you've migrated to tenant-scoped data.

The flip between modes is `.env` only — no code changes.
