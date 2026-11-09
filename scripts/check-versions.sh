#!/usr/bin/env bash
# Prints the current chart versions next to the ones pinned in this repo, so you can
# bump them deliberately. Run before the first deploy and then monthly.
# Requires: helm (with internet access).
set -euo pipefail
cd "$(dirname "$0")/.."

add() { helm repo add "$1" "$2" >/dev/null 2>&1 || true; }
add eks https://aws.github.io/eks-charts
add external-secrets https://charts.external-secrets.io
add argo https://argoproj.github.io/argo-helm
add metrics-server https://kubernetes-sigs.github.io/metrics-server/
add prometheus-community https://prometheus-community.github.io/helm-charts
add grafana https://grafana.github.io/helm-charts
add kyverno https://kyverno.github.io/kyverno
add chaos-mesh https://charts.chaos-mesh.org
helm repo update >/dev/null

latest() { helm search repo "$1" -o json | jq -r '.[0] | "\(.version) (app \(.app_version))"'; }

printf '%-34s %-22s %s\n' CHART PINNED LATEST
row() { printf '%-34s %-22s %s\n' "$1" "$2" "$(latest "$1")"; }

pin() { grep -hE -A0 "$1" "$2" | head -1 | sed -E 's/.*default += *"?([^"]+)"?.*/\1/'; }
ADDONS=terraform/modules/platform-addons/variables.tf
row eks/aws-load-balancer-controller "$(grep -A1 'alb_controller_chart_version' $ADDONS | grep default | sed -E 's/.*"(.*)".*/\1/')"
row external-secrets/external-secrets "$(grep -A1 'external_secrets_chart_version' $ADDONS | grep default | sed -E 's/.*"(.*)".*/\1/')"
row argo/argo-cd "$(grep -A1 'argocd_chart_version' $ADDONS | grep default | sed -E 's/.*"(.*)".*/\1/')"
row metrics-server/metrics-server "$(grep -A1 'metrics_server_chart_version' $ADDONS | grep default | sed -E 's/.*"(.*)".*/\1/')"

T=gitops/clusters/nonprod/platform-tools.yaml
tool() { # name chart
  printf '%-34s %-22s %s\n' "$2" "$(grep -A4 "name: $1\$" "$T" | grep 'version:' | head -1 | awk '{print $2}')" "$(latest "$2")"
}
tool argo-rollouts argo/argo-rollouts
tool kube-prometheus-stack prometheus-community/kube-prometheus-stack
tool loki grafana/loki
tool alloy grafana/alloy
tool tempo grafana/tempo
tool kyverno kyverno/kyverno
tool chaos-mesh chaos-mesh/chaos-mesh

echo
echo "ALB controller: if you bump the chart, also set alb_controller_policy_ref to the matching app version tag."
