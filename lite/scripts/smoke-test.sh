#!/usr/bin/env bash
# Usage: lite/scripts/smoke-test.sh [base-url]   (default http://localhost:8080)
# Checks the frontend and the API through the ingress (/readyz is not routed publicly by design).
set -euo pipefail
base="${1:-http://localhost:8080}"
fail=0
check() { # check <path> <expected-status>
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$base$1" || true)"
  if [ "$code" = "$2" ]; then echo "ok    $1 -> $code"; else echo "FAIL  $1 -> $code (wanted $2)"; fail=1; fi
}
check / 200
check /api/ping 200
exit "$fail"
