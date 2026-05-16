#!/usr/bin/env bash
#
# Bestie — one-shot local setup.
#
# Idempotent: safe to re-run. Creates a usable .env, generates a random
# 32-byte field-encryption key + JWT secrets, installs deps, runs the
# Prisma migration, and seeds the super admin.
#
# Re-runs that find an existing .env will only fill in keys that aren't set
# already, so your overrides survive.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env.example ]]; then
  echo "✖ .env.example missing — run from the backend directory" >&2
  exit 1
fi

# 1. Bootstrap .env -----------------------------------------------------------
if [[ ! -f .env ]]; then
  echo "→ creating .env from .env.example"
  cp .env.example .env
fi

# Generate any secret that's still at its template value.
set_if_blank() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=$" .env || grep -qE "^${key}=replace-me-" .env; then
    # Use a tmp file so we don't depend on sed's in-place quirks across BSD/GNU.
    awk -v k="$key" -v v="$value" 'BEGIN{set=0} {
      if (set==0 && $0 ~ "^"k"=") { print k"="v; set=1 } else { print }
    }' .env > .env.tmp && mv .env.tmp .env
    echo "  set $key"
  fi
}

set_if_blank JWT_ACCESS_SECRET     "$(node -e 'process.stdout.write(require("crypto").randomBytes(48).toString("base64url"))')"
set_if_blank JWT_REFRESH_SECRET    "$(node -e 'process.stdout.write(require("crypto").randomBytes(48).toString("base64url"))')"
set_if_blank FIELD_ENCRYPTION_KEY  "$(node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))')"

# Default DATABASE_URL to the docker-compose Postgres. Override in .env if
# you're pointing at something else.
if grep -qE "^DATABASE_URL=postgresql://bestie:bestie@localhost:5432/bestie\?schema=public$" .env; then
  : # already at the docker-compose default
elif ! grep -qE "^DATABASE_URL=postgresql://" .env; then
  echo "  set DATABASE_URL → postgresql://bestie:bestie@localhost:5432/bestie?schema=public"
  awk 'BEGIN{set=0} {
    if (set==0 && $0 ~ "^DATABASE_URL=") {
      print "DATABASE_URL=postgresql://bestie:bestie@localhost:5432/bestie?schema=public"
      set=1
    } else { print }
  }' .env > .env.tmp && mv .env.tmp .env
fi

# 2. npm install -------------------------------------------------------------
echo "→ npm install"
if [[ ! -d node_modules ]]; then
  npm install
else
  echo "  node_modules present, skipping (run \`npm install\` manually if you want a refresh)"
fi

# 3. Prisma migrate ----------------------------------------------------------
echo "→ npx prisma generate"
npx prisma generate >/dev/null

echo "→ npx prisma migrate dev --name init"
if [[ -d prisma/migrations ]]; then
  echo "  migrations dir present — applying pending only"
  npx prisma migrate deploy
else
  npx prisma migrate dev --name init
fi

# 4. Seed --------------------------------------------------------------------
echo "→ npm run seed"
npm run seed

echo ""
echo "✓ Bestie backend is set up."
echo ""
echo "  Start the API:     npm run dev"
echo "  Start the worker:  npm run worker   (separate terminal)"
echo "  Sign in with:      $(grep ^SEED_SUPER_ADMIN_USER_ID .env | cut -d= -f2)"
echo "                     $(grep ^SEED_SUPER_ADMIN_PASSWORD .env | cut -d= -f2)"
echo ""
