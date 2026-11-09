#!/usr/bin/env bash
# Deletes the local k3d cluster (and with it all data).
set -euo pipefail
k3d cluster delete "${CLUSTER_NAME:-eks-platform-lite}"
