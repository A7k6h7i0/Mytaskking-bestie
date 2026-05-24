# MyTaskKing — Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Cloudflare (DNS · SSL · CDN · DDoS)         │
└─────────────────────────────────────────────────────────────────────────┘
       │                                                            │
       ▼                                                            ▼
┌────────────────────────────┐                       ┌─────────────────────────┐
│  Flutter clients           │                       │  React web (admin /     │
│  • Android  • iOS          │                       │  company / client portal)│
│  • Windows  • macOS        │                       │  Served by Nginx static  │
└────────────┬───────────────┘                       └────────────┬─────────────┘
             │ HTTPS (REST) + WSS (Socket.IO)                     │
             └──────────────────────┬────────────────────────────┘
                                    ▼
                     ┌──────────────────────────────┐
                     │     Nginx (TLS terminate)    │
                     └──────────────┬───────────────┘
                                    ▼
                     ┌──────────────────────────────┐
                     │  Node.js · Express + Socket  │
                     │  PM2 cluster                 │
                     └─┬──────────┬──────────┬─────┘
                       │          │          │
            ┌──────────▼┐   ┌─────▼─────┐  ┌─▼────────────┐
            │ Postgres  │   │ Redis     │  │ Cron jobs    │
            │ (Prisma)  │   │ (presence/│  │ (expiry,     │
            │           │   │  pubsub)  │  │ followups)   │
            └───────────┘   └───────────┘  └──────────────┘

External integrations (adapter modules):
  • Cloudinary       — images
  • Cloudflare R2    — PDFs, files, attachments
  • Agora RTC        — voice calls (1:1 + group, recording)
  • Exotel           — telecaller click-to-call
  • Firebase FCM     — push notifications
```

## Why these choices

- **Single Node service, modular features.** Each module under `backend/src/modules/<feature>/` is a self-contained {service, routes, validators}. Promotes easy code review, predictable file paths, simple ownership.
- **Socket.IO + REST, not GraphQL.** Most actions are simple CRUD or fan-out to rooms; GraphQL adds complexity without saving round-trips here. Socket.IO already solves the realtime story.
- **Prisma over query-builders.** Lots of relations (channels ↔ members ↔ messages ↔ reactions, tasks ↔ assignees ↔ subtasks ↔ comments); a real ORM keeps these readable.
- **Adapters for third-parties.** `services/agora.js`, `services/exotel.js`, `services/cloudinary.js`, `services/r2.js`, `services/fcm.js` all degrade safely when credentials are missing — useful in dev/staging.
- **Cloudinary + R2, not S3.** Cloudinary's pipeline auto-optimizes images for every viewport. R2 is cheaper than S3 for documents and has no egress fees through Cloudflare's network.

## Auth model

- No public signup. **Admins provision every account** by user ID + password.
- JWT access (15 min default) + opaque refresh token (30 days default).
- Refresh tokens are hashed at rest and **rotated on every refresh** — reuse of an old token revokes the chain.
- Sockets use the same access token at handshake; the server re-checks client expiry on every connect.
- Roles are encoded in the JWT for fast middleware checks, but every protected mutation re-reads the user and verifies status. A suspended user with a still-valid JWT is rejected.

## Client access lifecycle

```
created  ─►  ACTIVE
             ▲   │
   extend()  │   │  accessEndsAt passes (cron at */15) OR admin disables
             │   ▼
             └─ EXPIRED  (login + auth + socket all return 410)
```

The `/15 * * * *` cron in `backend/src/jobs/index.js` is a safety net — every authenticated request also independently checks `accessEndsAt`.

## "Clients are red"

A visual contract enforced in three places:

- React: `--c-client` token, `UserName`/`Avatar` components, `client-name` CSS class.
- Flutter: `BestieTokens.cClient`, `BestieUserName`, `BestieAvatar` ring.
- Backend: every user payload includes `isClient: bool` so the client can render correctly without role-string parsing.

## Storage decision matrix

| Asset | Backend | Why |
|---|---|---|
| Profile photo, avatar | Cloudinary | auto-thumb, format negotiation |
| Chat image | Cloudinary | responsive sizing for mobile |
| PDF, report, doc | R2 | cheap, no egress, signed reads |
| Voice note | R2 | small audio, signed read |
| Call recording | R2 | large; written by recording service |

All assets are first-class rows in `FileAsset` so we always know where a URL came from and can move providers.

## Scaling notes

- Single Node process is fine to ~5k concurrent sockets. Beyond that, add the Socket.IO Redis adapter (`REDIS_URL` is already in `.env.example`) and let PM2 scale across cores.
- Postgres lives on the same VPS initially; move to managed when write volume warrants it. The schema indexes the hot paths (`messages.channelId+createdAt`, `tasks.status+order`, `leads.ownerId+status`).
- Calls don't fan media through us — Agora handles media. Socket.IO only carries signaling envelopes.
