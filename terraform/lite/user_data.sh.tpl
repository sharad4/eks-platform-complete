#!/bin/bash
# First-boot setup: swap, k3s, then the SAME bootstrap script as the local path.
# Log: /var/log/lite-bootstrap.log
set -euxo pipefail
exec > >(tee -a /var/log/lite-bootstrap.log) 2>&1

%{ if swap_gb > 0 ~}
fallocate -l ${swap_gb}G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
%{ endif ~}

dnf install -y git openssl

%{ if k3s_version != "" ~}
export INSTALL_K3S_VERSION='${k3s_version}'
%{ endif ~}
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

until kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 5; done

git clone --depth 1 --branch '${branch}' '${repo_url}' /opt/platform
cd /opt/platform
ARGOCD_VERSION='${argocd_version}' ARGOCD_MODE='${argocd_mode}' lite/scripts/bootstrap-cluster.sh
