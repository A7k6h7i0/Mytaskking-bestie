# MyTaskKing — Extension Architecture

How to add capabilities without coupling them to the core. Three extension surfaces matter most: **AI**, **offline / sync**, and **third-party providers**.

---

## 1. AI assistant, summaries, transcription, smart search

The platform has an `ai` service that ships as a no-op so nothing in the codebase depends on a specific provider. Wire a real one in by:

1. Set `AI_PROVIDER`, `AI_MODEL`, `AI_API_KEY` in `.env`.
2. Implement the relevant branch in [backend/src/services/ai.js](../backend/src/services/ai.js) — it already defines the four call shapes consumers expect (`summarize`, `transcribe`, `rerankSearch`, `insights`).
3. Nothing else changes — callers receive the new behavior automatically.

### Where AI plugs in naturally

| Capability | Where it hooks in |
|---|---|
| Task summarization | `tasks.service.js` `getById` — wrap result through `ai.summarize` when caller asks for `?summary=1` |
| Voice transcription | `services/agora.js` or a recording webhook — feed audio to `ai.transcribe`, store on `Call.recordingUrl` |
| Meeting summary | `calendar.routes.js` post-event hook — compose channel messages + recording transcript, run `ai.summarize` |
| Smart search rerank | `search.routes.js` — pipe the top-N candidates through `ai.rerankSearch` before responding |
| Weekly insights | `dashboard.service.js` — call `ai.insights({ scope: "weekly", payload: counts })` |

**Rule:** AI calls must always be opt-in or gated behind an admin setting (`settings.ai.enabled`). The platform must work without AI at all times.

---

## 2. Offline support (Flutter clients)

Designed so partial offline doesn't require a server-side rewrite.

### Cache layer

`bestie_core` keeps a local SQLite cache (suggested: `drift` or `sqflite`). Mirror these tables:

- `messages` — last 200 per channel
- `tasks` — all tasks where the user is creator or assignee
- `channels` — full membership list
- `notifications` — last 100
- `outbox` — pending mutations awaiting the network

### Outbox pattern

Every mutation (send message, move task, RSVP event, mark read) is:

1. Appended to `outbox` with a client-generated UUID.
2. Optimistically applied to the local cache.
3. Posted to the server. On success → drop the row. On failure → keep it, retry with backoff.

Conflict resolution is last-write-wins per record for chat/tasks; the backend already accepts client IDs idempotently for receipts (`MessageReceipt` is unique on `messageId+userId+state`).

### Sync triggers

- Socket reconnect → ask `/api/v1/sync?since=<ts>` (next addition) for a delta.
- App resume → flush outbox + delta-sync.
- Push notification arriving → wake up a sync isolate.

The web is intentionally not part of this: browsers handle offline poorly for chat-like workloads, and `react-query`'s in-memory cache covers the common "lost network for 30s" case.

---

## 3. Provider adapters (Agora, Exotel, Cloudinary, R2, FCM, Sentry)

All five exist as small modules under `backend/src/services/`. Each:

- exports a single object with named functions
- degrades to a safe no-op when its env vars are missing
- is imported lazily by the module that needs it

To swap (e.g. Exotel → Twilio): add `services/twilio.js` with the same shape (`connectCall`, webhook handler), then either flip a setting or change the import in `telecaller.service.js`. No other module knows about the provider.

---

## 4. Performance hooks

| Surface | Pattern |
|---|---|
| Large lists | Server returns cursors, not pages. Use `react-query`'s `useInfiniteQuery` or Flutter `ScrollController` to fetch as you scroll. |
| Realtime fan-out | Each `io.emit` targets a room (`channel:<id>`, `user:<id>`), never the whole namespace. |
| Image responsiveness | Always render through Cloudinary's `f_auto,q_auto,w_<n>` transform — the URL pattern in `services/cloudinary.js` returns the canonical one. |
| Background sync | Cron in `backend/src/jobs/index.js`; per-user heavy work goes via Redis-backed queues (drop in BullMQ when needed). |
| Caching strategies | `react-query` `staleTime: 30s` on dashboard; per-route ETag/`If-Modified-Since` on backend list endpoints (drop-in middleware). |
| Optimistic UI | Mutations should `setQueryData` immediately on submit, then reconcile on response. Errors trigger `toast.error` + rollback. |

---

## 5. Adding a new module — the recipe

```bash
backend/src/modules/<name>/
  ├── <name>.service.js   # pure business logic on prisma
  └── <name>.routes.js    # express router, joi validation, role guards
```

1. Write the service with no Express types — pure functions.
2. Write the router. Audit-log any state changes via `services/audit`.
3. Register in `backend/src/modules/index.js`.
4. Add to [docs/API.md](API.md).

Then on the frontend:

```bash
frontend/react_web/src/pages/<name>Page.tsx
frontend/react_web/src/pages/<name>.css   # optional, scoped class names
```

Wire into `App.tsx` and the appropriate role allowlist in `WorkspaceLayout`.
