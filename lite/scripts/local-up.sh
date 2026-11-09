#!/usr/bin/env bash
# Free local option (no AWS): a k3d cluster (k3s in Docker) on your laptop, then the same bootstrap
# as the EC2 path. Needs docker, k3d and kubectl. The cluster pulls manifests
# from your GitHub repo, so run lite/scripts/configure.sh and push first.
set -euo pipefail
cd "$(dirname "$0")/../.."

name="${CLUSTER_NAME:-eks-platform-lite}"
for bin in docker k3d kubectl openssl; do
  command -v "$bin" >/dev/null || { echo "Missing dependency: $bin" >&2; exit 1; }
done

if k3d cluster list "$name" >/dev/null 2>&1; then
  echo "Cluster $name already exists, reusing it."
else
  # Traefik (bundled with k3s) is exposed on http://localhost:8080
  k3d cluster create "$name" --servers 1 --agents 0 -p "8080:80@loadbalancer" --wait
fi
kubectl config use-context "k3d-$name" >/dev/null

lite/scripts/bootstrap-cluster.sh
echo
echo "App will be at http://localhost:8080 once the first image is built and synced."
