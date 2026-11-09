#!/usr/bin/env bash
# Stops the biggest non-prod costs outside working hours: worker nodes and the dev/staging databases.
#   scripts/nonprod-sleep.sh sleep   # evenings / weekends
#   scripts/nonprod-sleep.sh wake    # mornings
#
# What it saves: EC2 nodes (~$50-100/mo) and RDS instances (~$30-50/mo).
# What it does NOT save: EKS control plane ($73), NAT gateway, ALB, ElastiCache (cannot be stopped).
# Terraform will notice the changed min_size on its next plan; a normal `terraform apply` restores it.
# RDS auto-restarts after 7 days stopped (an AWS limit).
set -euo pipefail

ACTION="${1:?usage: nonprod-sleep.sh sleep|wake}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-eks-platform-nonprod}"
DBS=(eks-platform-dev eks-platform-staging)

scale() { # nodegroup min max desired
  aws eks update-nodegroup-config --region "$REGION" --cluster-name "$CLUSTER" --nodegroup-name "$1" \
    --scaling-config "minSize=$2,maxSize=$3,desiredSize=$4" >/dev/null
  echo "nodegroup $1 -> min=$2 max=$3 desired=$4"
}

case "$ACTION" in
  sleep)
    scale apps 0 6 0
    scale system 0 3 0
    for db in "${DBS[@]}"; do
      aws rds stop-db-instance --region "$REGION" --db-instance-identifier "$db" >/dev/null && echo "stopping $db" || echo "skip $db (already stopped?)"
    done
    ;;
  wake)
    for db in "${DBS[@]}"; do
      aws rds start-db-instance --region "$REGION" --db-instance-identifier "$db" >/dev/null && echo "starting $db" || echo "skip $db (already running?)"
    done
    scale system 2 3 2
    scale apps 2 6 2
    for db in "${DBS[@]}"; do aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$db"; done
    echo "Ready. Pods reschedule and ArgoCD reconciles on its own (allow ~5-10 minutes)."
    ;;
  *) echo "usage: nonprod-sleep.sh sleep|wake" >&2; exit 1 ;;
esac
