# Bestie API Reference

Base URL: `https://api.example.com/api/v1`

All authenticated endpoints require:

```
Authorization: Bearer <access token>
```

The error envelope is consistent across all routes:

```json
{ "error": { "code": "string", "message": "string", "details": "any?" } }
```

| Status | Code | Meaning |
|--------|------|---------|
| 400 | `bad_request` / `validation_error` | malformed input |
| 401 | `unauthorized` | missing / invalid / expired token |
| 403 | `forbidden` | role doesn't permit this |
| 404 | `not_found` | resource missing |
| 409 | `duplicate` / `conflict` | unique constraint |
| 410 | `gone` | client access window has expired |
| 429 | `too_many_requests` | rate limited |
| 500 | `internal_error` | server crashed |

---

## Auth

### `POST /auth/login`

Request:
```json
{ "userId": "priya.k", "password": "••••••" }
```
Response:
```json
{
  "user": { "id": "...", "userId": "priya.k", "name": "Priya K.", "role": "EMPLOYEE", "isClient": false, "status": "ACTIVE" },
  "accessToken": "...",
  "refreshToken": "...",
  "refreshExpiresAt": "2026-06-13T..."
}
```

### `POST /auth/refresh`
`{ "refreshToken": "..." }` → same shape as login.

### `POST /auth/logout`
`{ "refreshToken": "..." }` → `{ "ok": true }` (idempotent).

### `GET /auth/me`
Returns the authenticated user.

---

## Employees   *(admin only)*

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/employees?q&role&status&page&pageSize` | paginated list |
| `GET` | `/employees/:id` | get one |
| `POST` | `/employees` | create (admin assigns userId+password) |
| `PATCH` | `/employees/:id` | update fields, password, role |
| `POST` | `/employees/:id/suspend` / `/activate` | toggle status |
| `DELETE` | `/employees/:id` | remove |

`role` ∈ `ADMIN | EMPLOYEE | TELECALLER`.

---

## Clients   *(admin only)*

Same shape as Employees, plus:
- `accessStartsAt`, `accessEndsAt` (ISO datetimes)
- `clientCompany`

### `POST /clients/:id/extend`
`{ "accessEndsAt": "2026-12-31T23:59:59Z" }` — extends a client's access window.

### `POST /clients/:id/disable`
Immediately suspends a client (they can no longer authenticate).

> Client access is enforced **on every authenticated request** and on every Socket.IO connection. An expired client receives `410 Gone`.

---

## Channels

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/channels` | channels the caller is a member of (clients see only assigned channels) |
| `POST` | `/channels` | create (`kind` ∈ `DM, GROUP, PROJECT, ANNOUNCEMENT, CLIENT`) |
| `GET` | `/channels/:id` | details + members |
| `POST` | `/channels/:id/members` | add members |
| `DELETE` | `/channels/:id/members/:memberId` | remove |
| `POST` | `/channels/:id/pin` / `/unpin` | pin to top *(admin)* |
| `POST` | `/channels/:id/archive` / `/unarchive` | archive *(admin)* |

Channels that contain at least one client are flagged `isClientChannel: true`.

---

## Chat

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/chat/channels/:channelId/messages?cursor&limit` | paged history (cursor = id, newest-first then reversed) |
| `POST` | `/chat/channels/:channelId/messages` | send |
| `PATCH` | `/chat/messages/:id` | edit (author only) |
| `DELETE` | `/chat/messages/:id` | delete (author or admin) |
| `POST` | `/chat/messages/:id/react` / `/unreact` | emoji reaction toggle |
| `POST` | `/chat/messages/:id/pin` / `/unpin` | pin message |
| `POST` | `/chat/channels/:channelId/read` | mark read |

Send body:
```json
{
  "body": "Hi team",
  "kind": "TEXT|IMAGE|FILE|VOICE_NOTE",
  "attachmentIds": ["fileAssetId", "..."],
  "replyToId": null
}
```

---

## Tasks

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/tasks?view=list\|kanban\|calendar&status&assigneeId&q&page` | list or kanban (`columns: { TODO: [...], … }`) |
| `GET` | `/tasks/:id` | details |
| `POST` | `/tasks` | create |
| `PATCH` | `/tasks/:id` | update (assignees: replace set) |
| `POST` | `/tasks/:id/move` | `{ status, order }` — used during kanban drag |
| `DELETE` | `/tasks/:id` | delete |
| `POST` | `/tasks/:id/comments` | add comment |
| `POST` | `/tasks/:id/subtasks` | add subtask |
| `PATCH` | `/tasks/subtasks/:id` | `{ done: true|false }` |

---

## Calls   *(Agora)*

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/calls/initiate` | start ringing — server returns Agora `channelName` + RTC tokens, one per participant |
| `GET` | `/calls/:id/token` | refresh my Agora token |
| `POST` | `/calls/:id/join` | mark participant joined |
| `POST` | `/calls/:id/leave` | leave |
| `POST` | `/calls/:id/participants` | add participant mid-call (auto-promotes 1:1 → group) |
| `POST` | `/calls/:id/mute` | `{ muted: bool }` |
| `GET` | `/calls/history?page&pageSize` | history |

Initiate request:
```json
{ "participantIds": ["..."], "kind": "ONE_TO_ONE|GROUP", "channelId": "optional" }
```

---

## Telecaller   *(Exotel)*

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/telecaller/leads?q&status&ownerId&page` | leads (telecallers see only their own) |
| `POST` | `/telecaller/leads` | create lead |
| `GET` | `/telecaller/leads/:id` | with recent calls |
| `PATCH` | `/telecaller/leads/:id` | update status, owner, notes, next follow |
| `POST` | `/telecaller/leads/:id/call` | **click-to-call** via Exotel |
| `GET` | `/telecaller/calls` | call history |
| `GET` | `/telecaller/followups/today` | followups due today |
| `POST` | `/telecaller/webhook` | **Exotel callback** (unauthenticated, called by Exotel) |

---

## Files

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/files/upload` (multipart `file`) | server-side upload. Images → Cloudinary, others → R2. |
| `POST` | `/files/sign/cloudinary` | params for direct-upload to Cloudinary |
| `POST` | `/files/sign/r2` | `{ filename, contentType, folder }` → presigned PUT |
| `POST` | `/files/register` | after direct upload, register the asset |
| `GET` | `/files/:id/signed-url` | signed download URL |

---

## Notifications   *(FCM)*

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/notifications?page` | my notifications |
| `POST` | `/notifications/read-all` | mark all read |
| `POST` | `/notifications/:id/read` | mark single read |
| `POST` | `/notifications/devices` | `{ token, platform: ANDROID|IOS|WEB|WINDOWS|MACOS }` |
| `DELETE` | `/notifications/devices/:token` | unregister device |

---

## Dashboard

`GET /dashboard/overview` — content depends on caller's role:
- super_admin / admin → org-wide counts + activity log
- employee / telecaller → personal counts
- client → channels + access window

---

## Realtime — Socket.IO

`/socket.io` with `auth: { token: <access JWT> }`.

| Event | From | Payload |
|---|---|---|
| `presence.update` | server | `{ userId, online: bool }` |
| `channel.join` / `channel.leave` | client | `channelId` |
| `chat.message.created` / `.updated` / `.deleted` | server | message |
| `chat.typing` | client → server → channel | `{ channelId, typing }` |
| `task.created` / `.updated` / `.moved` / `.deleted` / `.comment` | server | task or `{taskId, comment}` |
| `call.incoming` | server → invited user | `{ call, token }` |
| `call.participant.joined` / `.left` / `.muted` | server | `{ callId, userId, … }` |
| `call.signal` | peer-to-peer | `{ to, payload }` — generic signaling channel for negotiation outside Agora |
| `call.screen_share.started` / `.stopped` | server | `{ callId, userId }` |
| `call.hand_raised` | server | `{ callId, userId, raised }` |
| `call.speaking` | server | `{ callId, userId, volume }` |
| `chat.message.receipt` / `.receipts.bulk` | server | per-user delivered/seen state |
| `announcement.published` | server | full announcement payload |
| `calendar.event.created` / `.updated` | server | event payload |
| `activity.recorded` | server | `{ kind, entity, entityId, actorId, at }` |

All events check the user is still authorized for the channel/task at emit time. Server enforces client expiry on socket connect too.

---

## Audit log   *(admin only)*

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/audit?q&kind&actorId&entity&from&to&cursor&limit` | paginated activity timeline |
| `GET` | `/audit/kinds` | most-used event kinds, for filter chips |

`kind` prefixes — `auth.*`, `employee.*`, `client.*`, `channel.*`, `message.*`, `task.*`, `call.*`, `telecaller.*`, `file.*`, `settings.*`, `announcement.*`, `permission.*`.

## Global search

`GET /search?q&perEntity&kinds` returns up to `perEntity` (default 6) hits in each of `users`, `channels`, `tasks`, `messages`, `files`, `leads`. Clients only see their own assigned channels / tasks / files.

## Saved items

| Method | Path | Body | Purpose |
|---|---|---|---|
| `GET` | `/saved?kind` | — | list with hydrated target |
| `POST` | `/saved` | `{ kind, refId, note? }` | bookmark / star |
| `DELETE` | `/saved` | `{ kind, refId }` | remove |

`kind` ∈ `MESSAGE | FILE | TASK | CHANNEL | LEAD`.

## Workspace settings

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/settings?scope` | scoped key/value pairs (open to any authed user) |
| `PUT` | `/settings/:scope/:key` | upsert *(admin)* |
| `DELETE` | `/settings/:scope/:key` | clear *(admin)* |

Common scopes — `branding`, `permissions`, `retention`, `notifications`, `channelDefaults`.

## Calendar

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/calendar?from&to&view=day\|week\|month` | events in range owned by or attended by me |
| `POST` | `/calendar` | create event |
| `PATCH` | `/calendar/:id` | update (owner / admin) |
| `POST` | `/calendar/:id/rsvp` | `{ status: ACCEPTED \| DECLINED \| TENTATIVE }` |
| `DELETE` | `/calendar/:id` | delete |

## Announcements

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/announcements` | live announcements visible to caller |
| `POST` | `/announcements` | publish *(admin)* — `scope`, `priority`, `publishAt`, `expiresAt`, `notify` |
| `POST` | `/announcements/:id/ack` | dismiss for the current user |
| `DELETE` | `/announcements/:id` | remove *(admin)* |

## Chat receipts

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/chat/messages/:id/receipt` | `{ state: DELIVERED \| SEEN }` |
| `POST` | `/chat/channels/:channelId/receipts/bulk` | `{ messageIds, state }` — used on scroll-into-view |

## Calls — advanced

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/calls/:id/screen-share/token` | mint a screen-share UID + Agora token |
| `POST` | `/calls/:id/screen-share/stop` | broadcast stop |
| `POST` | `/calls/:id/raise-hand` | `{ raised: bool }` |
| `POST` | `/calls/:id/speaking` | `{ volume: 0-255 }` — periodic active-speaker telemetry |

## Channel permissions

| Method | Path | Purpose |
|---|---|---|
| `PATCH` | `/channels/:id/policy` | channel-wide defaults (`defaultCanPost`, `defaultCanUpload`, `defaultCanInvite`, `defaultCanCreateTask`, `retentionDays`) |
| `PATCH` | `/channels/:id/members/:memberId` | per-member overrides + `memberRole` ∈ `OWNER \| ADMIN \| MODERATOR \| MEMBER \| READONLY` |

## Files — versions

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/files/:id/versions` (multipart `file`) | upload a new version, becomes current |
| `GET` | `/files/:id/versions` | version history |
| `PATCH` | `/files/:id/category` | tag with category / preview URL |

`GET /files/:id/signed-url` also writes a `FileDownload` row for audit + analytics.

## Monitoring

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/metrics` | Prometheus-format metrics |

Set `SENTRY_DSN` to enable Sentry error tracking — request + error handlers are pre-installed.
