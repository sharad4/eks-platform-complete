#!/usr/bin/env bash
# Post-deploy verification. Usage: BASE_URL=https://staging.example.com scripts/smoke-test.sh
# Exits non-zero on the first failing check, so it can gate a pipeline step.
set -euo pipefail

: "${BASE_URL:?Set BASE_URL, e.g. https://dev.example.com}"
BASE_URL="${BASE_URL%/}"
RETRIES="${RETRIES:-12}"
SLEEP="${SLEEP:-10}"

check() {
  local name="$1" url="$2" expect="$3" attempt=1 code
  while [ "$attempt" -le "$RETRIES" ]; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$url" || echo 000)"
    if [ "$code" = "$expect" ]; then
      echo "PASS  $name ($url -> $code)"
      return 0
    fi
    echo "wait  $name: got $code, want $expect (attempt $attempt/$RETRIES)"
    attempt=$((attempt + 1))
    sleep "$SLEEP"
  done
  echo "FAIL  $name ($url)"
  return 1
}

check "frontend serves the SPA"   "$BASE_URL/"          200
check "frontend health"           "$BASE_URL/healthz"   200
check "backend reachable via ALB" "$BASE_URL/api/ping"  200

# The backend must also behave: JSON with the expected key.
if curl -sS --max-time 10 "$BASE_URL/api/ping" | grep -q '"pong"'; then
  echo "PASS  backend payload"
else
  echo "FAIL  backend payload"
  exit 1
fi

# /metrics must NOT be reachable from the internet (the ALB only routes / and /api).
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL/api/metrics" || echo 000)"
if [ "$code" = "200" ]; then
  echo "FAIL  metrics endpoint is publicly reachable"
  exit 1
fi
echo "PASS  metrics not exposed publicly"
echo "All smoke checks passed."
