# MyTaskKing — Enterprise Company Management Platform

Premium enterprise collaboration and management platform: internal company collaboration, employee + client management, realtime chat, advanced task management, telecaller CRM, group channels, voice calling, desktop + mobile + web.

## Stack

| Layer | Tech |
|---|---|
| Mobile + Desktop | Flutter (Android, iOS, Windows, macOS) |
| Web | React 18 + Vite + TypeScript |
| Backend API | Node.js + Express |
| Realtime | Socket.IO |
| Database | PostgreSQL 16 (or MySQL 8) via Prisma |
| Voice Calls | Agora RTC |
| Telecaller | Exotel API |
| Images | Cloudinary |
| Files / PDFs | Cloudflare R2 |
| Push | Firebase Cloud Messaging |
| CDN / DNS / SSL | Cloudflare |
| Process Manager | PM2 |
| Reverse Proxy | Nginx |

## Monorepo Layout

```
bestie/
├── backend/                Node.js + Express + Socket.IO + Prisma
├── frontend/
│   ├── react_web/          Admin panel, Company dashboard, Client portal
│   └── flutter_apps/
│       ├── mobile_app/     Android + iOS
│       ├── windows_app/    Windows desktop
│       ├── macos_app/      macOS desktop
│       ├── shared_design_system/
│       └── shared_core/    API client, models, state
├── deploy/                 PM2, nginx, docker
└── docs/                   API reference, architecture
```

## Quick start (backend)

First, start Postgres. The repo ships a `deploy/docker-compose.yml` that boots one — `docker compose -f deploy/docker-compose.yml up -d postgres`.

Then bootstrap the backend in one shot:

```bash
cd backend
npm run setup
```

`npm run setup` is idempotent. It creates a `.env` if missing, generates strong JWT and field-encryption secrets, installs dependencies, runs the Prisma migration, and seeds the super-admin. Re-run it after pulling new migrations.

Then:

```bash
npm run dev               # API at http://localhost:4000
npm run worker            # in a second terminal — drains background jobs
```

Default login (printed at the end of `setup`):

```
user id:   superadmin
password:  Change-Me-Now!     # change immediately
```

## Quick start (web)

```bash
cd frontend/react_web
cp .env.example .env
npm install
npm run dev                   # http://localhost:5173
```

## Authentication

- No email / phone login.
- Super-admin / admin manually provisions every account.
- Login is **User ID + Password** only.
- JWT access token + refresh token, RBAC on every route + socket event.
- Clients have access windows; expiry is enforced server-side on every request.

## Roles

- **super_admin** — full access
- **admin** — manages employees, clients, channels, tasks, telecallers
- **employee** — internal collaboration + chat + calls + tasks
- **telecaller** — leads, click-to-call, followups
- **client** — limited access to assigned channels/files only. Displayed in **red** everywhere.

## Docs

- [docs/API.md](docs/API.md) — full REST + Socket.IO reference
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design
- [docs/EXTENSIONS.md](docs/EXTENSIONS.md) — adding modules, AI, offline
- [docs/ENTERPRISE.md](docs/ENTERPRISE.md) — multi-tenancy, advanced RBAC, sessions, automations, analytics, AI roadmap
- [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md) — event bus, cache, queues, distributed sockets, media pipeline, observability, CI/CD, feature flags, collaboration
- Live OpenAPI reference at `/api/v1/docs` once the backend is running.
