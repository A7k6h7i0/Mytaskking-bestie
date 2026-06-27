#!/usr/bin/env bash
# Run ON THE PRODUCTION SERVER (SSH) — not on your laptop.
# Checks that multi-tenant login is ready before testing the mobile app.

set -euo pipefail

API="${PUBLIC_API_URL:-https://mytaskking.com}"

echo "==> Health"
curl -sS "$API/health/ready" | python3 -m json.tool 2>/dev/null || curl -sS "$API/health/ready"
echo

echo "==> Login probe (expect 401 invalid credentials, NOT 500)"
HTTP=$(curl -sS -o /tmp/login-probe.json -w "%{http_code}" \
  -X POST "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"tenantSlug":"default","userId":"probe-user","password":"wrongpass12"}')
echo "HTTP $HTTP"
cat /tmp/login-probe.json
echo

if [ "$HTTP" = "500" ]; then
  echo "FAIL: login still returns 500 — DB migration or backend deploy missing."
  echo "On this server: cd backend && npx prisma migrate deploy && set MULTI_TENANT=true && restart API"
  exit 1
fi

echo "OK: login endpoint responding (401/403 is fine for wrong password)."
