#!/usr/bin/env bash
# Turns an empty single-node Kubernetes cluster (k3s or k3d) into the lite
# platform. Used by BOTH the AWS user-data and the local k3d script, and safe
# to re-run: existing Secrets are reused, never regenerated.
#
# Needs: kubectl (pointing at the cluster), openssl, base64, internet access.
# Optional env:
#   ARGOCD_VERSION  git ref of argo-cd manifests (default: stable)
#   ARGOCD_MODE     core (no UI, ~half the RAM; default) | full
#   GHCR_USER, GHCR_TOKEN   create an image pull secret for private GHCR packages
set -euo pipefail
cd "$(dirname "$0")/../.."

ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
ARGOCD_MODE="${ARGOCD_MODE:-core}"
case "$ARGOCD_MODE" in
  core) manifest=core-install.yaml ;;
  full) manifest=install.yaml ;;
  *) echo "ARGOCD_MODE must be core or full" >&2; exit 1 ;;
esac

if grep -rq --include='*.yaml' -E '__GITHUB_(ORG|REPO)' lite/gitops; then
  echo "Run lite/scripts/configure.sh first (and push), tokens are still unset." >&2
  exit 1
fi

echo "==> Namespaces"
kubectl apply -f lite/gitops/bootstrap/namespaces.yaml

# --- Secrets: generated once, kept in the cluster only (never in Git) ---------
existing() { # existing <namespace> <secret> <key>
  kubectl -n "$1" get secret "$2" -o "jsonpath={.data.$3}" 2>/dev/null | base64 -d 2>/dev/null || true
}
or_new() { # or_new <existing-value> <generator command...>
  local cur="$1"; shift
  if [ -n "$cur" ]; then printf '%s' "$cur"; else "$@"; fi
}
gen_hex() { openssl rand -hex 24; }
gen_app_key() { printf 'base64:%s' "$(openssl rand -base64 32)"; }

apply_env_secret() { # apply_env_secret <namespace> <name> <env-file>
  kubectl -n "$1" create secret generic "$2" --from-env-file="$3" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

echo "==> Secrets"
umask 077
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT

db_pass="$(or_new "$(existing data postgres-auth POSTGRES_PASSWORD)" gen_hex)"
redis_pass="$(or_new "$(existing data redis-auth REDIS_PASSWORD)" gen_hex)"
app_key="$(or_new "$(existing lite backend-secrets APP_KEY)" gen_app_key)"

printf 'POSTGRES_USER=app\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=app\n' "$db_pass" >"$tmp"
apply_env_secret data postgres-auth "$tmp"
printf 'REDIS_PASSWORD=%s\n' "$redis_pass" >"$tmp"
apply_env_secret data redis-auth "$tmp"
printf 'APP_KEY=%s\nDB_USERNAME=app\nDB_PASSWORD=%s\nREDIS_PASSWORD=%s\n' \
  "$app_key" "$db_pass" "$redis_pass" >"$tmp"
apply_env_secret lite backend-secrets "$tmp"

if [ -n "${GHCR_USER:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
  kubectl -n lite create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io --docker-username="$GHCR_USER" --docker-password="$GHCR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "    created ghcr-pull"
fi

echo "==> Argo CD ($ARGOCD_MODE, $ARGOCD_VERSION)"
kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
# Server-side apply: the Argo CD CRDs exceed the client-side annotation size limit.
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/${manifest}"
kubectl wait --for=condition=established --timeout=120s crd/applications.argoproj.io
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Root application"
kubectl apply -f lite/gitops/bootstrap/default-project.yaml
kubectl apply -f lite/gitops/bootstrap/root.yaml

cat <<MSG

Bootstrap complete. Argo CD now syncs lite/gitops/ from GitHub.
  watch:    kubectl -n argocd get applications
  UI:       $( [ "$ARGOCD_MODE" = full ] && echo "kubectl -n argocd port-forward svc/argocd-server 8081:443  (user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" || echo "core mode has no UI; use the CLI: argocd admin dashboard -n argocd (or re-run with ARGOCD_MODE=full)" )
  Pods stay in ImagePullBackOff until CI has pushed the first image and bumped the tag.
MSG