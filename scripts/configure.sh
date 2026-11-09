#!/usr/bin/env bash
# Replaces the __TOKENS__ in gitops/ with your real values, in one pass.
#
#   GITHUB_ORG=acme GITHUB_REPO=eks-platform ACCOUNT_ID=123456789012 REGION=us-east-1 \
#   DOMAIN=example.com CERT_ARN_DEV=arn:... CERT_ARN_STAGING=arn:... CERT_ARN_PRODUCTION=arn:... \
#   scripts/configure.sh
#
# DB secret ARNs are read from Terraform outputs when available (apply Layer 1 first),
# or can be given as DB_SECRET_ARN_DEV / _STAGING / _PRODUCTION.
set -euo pipefail
cd "$(dirname "$0")/.."

need() { [ -n "${!1:-}" ] || { echo "Missing required variable: $1" >&2; exit 1; }; }
for v in GITHUB_ORG GITHUB_REPO ACCOUNT_ID REGION DOMAIN; do need "$v"; done

tf_out() { terraform -chdir="$1" output -json "$2" 2>/dev/null || true; }

if [ -z "${DB_SECRET_ARN_DEV:-}" ] && [ -d terraform/environments/nonprod/.terraform ]; then
  json="$(tf_out terraform/environments/nonprod db_master_secret_arns)"
  if [ -n "$json" ]; then
    DB_SECRET_ARN_DEV="$(jq -r '.dev // empty' <<<"$json")"
    DB_SECRET_ARN_STAGING="$(jq -r '.staging // empty' <<<"$json")"
  fi
fi
if [ -z "${DB_SECRET_ARN_PRODUCTION:-}" ] && [ -d terraform/environments/prod/.terraform ]; then
  DB_SECRET_ARN_PRODUCTION="$(terraform -chdir=terraform/environments/prod output -raw db_master_secret_arn 2>/dev/null || true)"
fi

replace() {
  local token="$1" value="${2:-}"
  [ -n "$value" ] || { echo "skip   $token (no value)"; return 0; }
  # '|' as the sed delimiter because ARNs contain '/' and ':'
  grep -rl --include='*.yaml' "$token" gitops helm monitoring security chaos 2>/dev/null \
    | xargs -r sed -i "s|$token|$value|g"
  echo "set    $token"
}

replace __GITHUB_ORG__ "$GITHUB_ORG"
replace __GITHUB_REPO__ "$GITHUB_REPO"
replace __ACCOUNT_ID__ "$ACCOUNT_ID"
replace __REGION__ "$REGION"
replace __DOMAIN__ "$DOMAIN"
replace __CERT_ARN_DEV__ "${CERT_ARN_DEV:-}"
replace __CERT_ARN_STAGING__ "${CERT_ARN_STAGING:-}"
replace __CERT_ARN_PRODUCTION__ "${CERT_ARN_PRODUCTION:-}"
replace __DB_SECRET_ARN_DEV__ "${DB_SECRET_ARN_DEV:-}"
replace __DB_SECRET_ARN_STAGING__ "${DB_SECRET_ARN_STAGING:-}"
replace __DB_SECRET_ARN_PRODUCTION__ "${DB_SECRET_ARN_PRODUCTION:-}"

echo
if grep -rn --include='*.yaml' -E '__[A-Z_]+__' gitops helm monitoring security chaos 2>/dev/null; then
  echo "WARNING: the tokens above are still unset." >&2
else
  echo "All tokens replaced. Review with 'git diff', then commit and push."
fi
