# Bestie Web

React 18 + Vite + TypeScript. Renders the Admin Panel, the Company Dashboard, and the Client Portal from one codebase — the role on the authenticated user decides what they see.

## Run

```bash
cp .env.example .env       # set VITE_API_URL
npm install
npm run dev                # http://localhost:5173
```

## Layout

```
src/
├── styles/         tokens.css (shared with Flutter), global.css
├── components/ui/  Button, Input, Avatar, UserName, …
├── layouts/        WorkspaceLayout (sidebar + topbar)
├── pages/          Login, Dashboard, Chat, Channels, Tasks, Calls, Telecaller, Employees, Clients
├── services/       api (axios + refresh), socket (io-client)
├── store/          zustand auth store with persistence
└── App.tsx         routing + role gates
```

## Design system

`src/styles/tokens.css` is the single source of truth for color, radius, spacing, type, motion. It mirrors `frontend/flutter_apps/shared_design_system/lib/src/tokens.dart` token-for-token — keep them in sync when one changes.

Clients are always rendered in `--c-client` via the `<UserName>` component and the `.client-name` class. Don't override it.

## Build

```bash
npm run build              # outputs to dist/
```

Deploy `dist/` behind Nginx; see [../../deploy/nginx.conf.sample](../../deploy/nginx.conf.sample).
