#!/usr/bin/env bash
# Guided "deploy from zero" for ONE environment, after terraform/bootstrap is applied.
# Every step is something you could run by hand; this just keeps the order straight.
#
# Usage: scripts/bootstrap.sh nonprod|prod
set -euo pipefail

ENV="${1:?usage: bootstrap.sh nonprod|prod}"
case "$ENV" in nonprod|prod) ;; *) echo "env must be nonprod or prod" >&2; exit 1 ;; esac
cd "$(dirname "$0")/.."

for tool in terraform kubectl aws; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
for f in "terraform/environments/$ENV/backend.hcl" "terraform/environments/$ENV/terraform.tfvars" \
         "terraform/addons/$ENV/backend.hcl" "terraform/addons/$ENV/terraform.tfvars"; do
  [ -f "$f" ] || { echo "Missing $f (copy the .example file next to it and fill it in)" >&2; exit 1; }
done

step() { printf '\n==> %s\n' "$*"; }

step "Layer 1: network, cluster, data (15-25 min)"
terraform -chdir="terraform/environments/$ENV" init -backend-config=backend.hcl
terraform -chdir="terraform/environments/$ENV" apply

step "Connect kubectl"
eval "$(terraform -chdir="terraform/environments/$ENV" output -raw kubeconfig_command)"
kubectl get nodes

step "Layer 2: controllers (ALB, External Secrets, ArgoCD, metrics-server)"
terraform -chdir="terraform/addons/$ENV" init -backend-config=backend.hcl
terraform -chdir="terraform/addons/$ENV" apply

step "Hand over to GitOps"
echo "Did you run scripts/configure.sh and push to GitHub? ArgoCD can only deploy what is in Git."
read -r -p "Apply the root application now? [y/N] " yn
[ "$yn" = "y" ] || { echo "Skipped. Later: kubectl apply -f gitops/bootstrap/root-$ENV.yaml"; exit 0; }
kubectl apply -f "gitops/bootstrap/root-$ENV.yaml"

step "Watch it converge"
echo "  kubectl -n argocd get applications -w"
echo "  $(terraform -chdir="terraform/addons/$ENV" output -raw argocd_port_forward)"
echo "  $(terraform -chdir="terraform/addons/$ENV" output -raw argocd_admin_password_command)"
