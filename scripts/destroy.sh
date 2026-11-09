#!/usr/bin/env bash
# Safe teardown for an environment: removes what Kubernetes created in AWS (ALBs,
# volumes) BEFORE Terraform tries to delete the VPC. Skipping this is the classic
# reason `terraform destroy` hangs on subnets for 20+ minutes.
#
# Usage: scripts/destroy.sh nonprod|prod
set -euo pipefail

ENV="${1:?usage: destroy.sh nonprod|prod}"
case "$ENV" in nonprod|prod) ;; *) echo "env must be nonprod or prod" >&2; exit 1 ;; esac
cd "$(dirname "$0")/.."

echo "This DESTROYS the $ENV environment (cluster, databases, caches)."
read -r -p "Type the environment name to confirm: " answer
[ "$answer" = "$ENV" ] || { echo "aborted"; exit 1; }

echo "==> Stopping ArgoCD from re-creating things"
kubectl -n argocd delete application root --ignore-not-found --wait=true || true
kubectl -n argocd delete applicationset --all --ignore-not-found || true

echo "==> Deleting Ingresses so the ALB controller removes the load balancers"
kubectl delete ingress --all --all-namespaces --ignore-not-found --wait=true || true

echo "==> Deleting PVCs so EBS volumes are released"
kubectl delete pvc --all --all-namespaces --ignore-not-found --wait=true || true

echo "==> Waiting 60s for AWS to finish deleting load balancers"
sleep 60

echo "==> Destroying add-ons layer, then infrastructure layer"
terraform -chdir="terraform/addons/$ENV" destroy -auto-approve
terraform -chdir="terraform/environments/$ENV" destroy
echo "Done. (The bootstrap state bucket is kept on purpose; remove it manually if you are done with the account.)"
