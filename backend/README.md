# MyTaskKing Backend

Node.js + Express + Prisma + Socket.IO. PM2 in production, Nginx in front, Cloudflare at the edge.

## Run

```bash
cp .env.example .env       # fill in DATABASE_URL + JWT secrets
npm install
npx prisma migrate dev     # creates schema
npm run seed               # bootstraps the super admin from .env values
npm run dev                # http://localhost:4000
```

Health check: `GET /health` → `{ ok: true }`.

## Layout

```
src/
├── app.js                  HTTP + Socket.IO entry
├── config/                 env-driven config object
├── database/               prisma client + seed
├── jobs/                   cron — client expiry, followup reminders
├── middleware/             auth, error handler, validate, rate limit
├── modules/                feature modules (auth, employees, clients, channels, chat, tasks, calls, telecaller, notifications, dashboard, files)
├── services/               third-party adapters (agora, exotel, cloudinary, r2, fcm, tokens)
├── sockets/                Socket.IO server with JWT auth + presence
└── utils/                  errors, logger, asyncHandler
```

Each module under `modules/<name>/` has:
- `<name>.service.js` — pure business logic, works with `prisma`
- `<name>.routes.js` — Express router, Joi validation, role guards

## Production

```bash
npm install --omit=dev
npx prisma generate
pm2 start ecosystem.config.js
```

See [../deploy/nginx.conf.sample](../deploy/nginx.conf.sample) for the reverse proxy + WSS upgrade.
