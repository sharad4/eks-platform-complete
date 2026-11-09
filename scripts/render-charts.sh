#!/usr/bin/env bash
# Lint and render the chart for every workload, offline (no cluster needed).
# Used locally and by CI. Requires: helm. Optional: kubeconform.
set -euo pipefail

CHART="$(cd "$(dirname "$0")/.." && pwd)/helm/app"
OUT="${OUT:-/tmp/rendered}"
mkdir -p "$OUT"

declare -A FILES=(
  [backend]="values/laravel-common.yaml values/backend.yaml"
  [frontend]="values/frontend.yaml"
  [worker]="values/laravel-common.yaml values/worker.yaml"
)

for app in backend frontend worker; do
  args=()
  for f in ${FILES[$app]}; do args+=(-f "$CHART/$f"); done
  args+=(-f "$CHART/ci/test-values.yaml")

  echo "==> lint $app"
  helm lint "$CHART" "${args[@]}" --strict

  echo "==> template $app"
  helm template "$app" "$CHART" "${args[@]}" > "$OUT/$app.yaml"

  if command -v kubeconform >/dev/null; then
    # -ignore-missing-schemas: ExternalSecret / ServiceMonitor CRDs have no built-in schema
    kubeconform -strict -summary -ignore-missing-schemas "$OUT/$app.yaml"
  fi
done

# Second pass: backend with the canary + migration code paths switched on.
echo "==> lint backend (rollout + migration)"
args=(-f "$CHART/values/laravel-common.yaml" -f "$CHART/values/backend.yaml" -f "$CHART/ci/test-values.yaml" -f "$CHART/ci/test-rollout.yaml")
helm lint "$CHART" "${args[@]}" --strict
helm template backend "$CHART" "${args[@]}" > "$OUT/backend-rollout.yaml"
grep -q "kind: Rollout" "$OUT/backend-rollout.yaml" || { echo "Rollout was not rendered"; exit 1; }
grep -q "kind: AnalysisTemplate" "$OUT/backend-rollout.yaml" || { echo "AnalysisTemplate was not rendered"; exit 1; }

echo "Rendered manifests are in $OUT"
