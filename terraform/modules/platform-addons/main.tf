# =============================================================================
# Platform add-ons: the controllers that make a bare EKS cluster usable.
#
#   metrics-server   -> feeds `kubectl top` and the HPA (no metrics = no autoscaling)
#   ALB controller   -> turns Ingress objects into AWS Application Load Balancers
#   External Secrets -> syncs AWS Secrets Manager into Kubernetes Secrets
#   ArgoCD           -> GitOps engine; after this, everything else is pulled from Git
#
# These are installed by Terraform (not ArgoCD) because they are prerequisites
# for ArgoCD itself to be useful. This is the classic bootstrap trade-off:
# Terraform owns the cluster + the few things GitOps depends on; ArgoCD owns
# everything above that.
#
# Controllers that talk to AWS get their own IRSA role. None use the node role.
# =============================================================================

locals {
  replicas = var.high_availability ? 2 : 1
}

# -----------------------------------------------------------------------------
# metrics-server
# -----------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  atomic  = true
  timeout = 300

  values = [yamlencode({
    replicas = local.replicas
  })]
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# -----------------------------------------------------------------------------
# The controller needs a large IAM policy (ELB, EC2, WAF, Shield, ACM...).
# Fetching the upstream file at a PINNED TAG avoids hand-copying 200+ lines and
# keeps it in sync with the controller version. Trade-off: plan needs internet
# access to raw.githubusercontent.com; vendor the file into the repo if you
# need hermetic builds.
data "http" "alb_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.alb_controller_policy_ref}/docs/install/iam_policy.json"

  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not download the ALB controller IAM policy for ${var.alb_controller_policy_ref}."
    }
  }
}

module "alb_irsa" {
  source = "../iam-irsa"

  name              = "${var.cluster_name}-alb-controller"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_json       = data.http.alb_policy.response_body
  tags              = var.tags
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  atomic  = true
  timeout = 600

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = local.replicas

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.alb_irsa.role_arn
      }
    }

    # Keep controller pods off one node so a node drain cannot stop LB reconciliation.
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "kubernetes.io/hostname"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "aws-load-balancer-controller"
        }
      }
    }]
  })]

  depends_on = [helm_release.metrics_server]
}

# -----------------------------------------------------------------------------
# External Secrets Operator
# -----------------------------------------------------------------------------
module "eso_irsa" {
  source = "../iam-irsa"

  name              = "${var.cluster_name}-external-secrets"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  namespace         = "external-secrets"
  service_account   = "external-secrets"
  policy_json       = var.eso_read_policy_json
  tags              = var.tags
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version

  atomic  = true
  timeout = 600

  values = [yamlencode({
    installCRDs  = true
    replicaCount = local.replicas

    serviceAccount = {
      create = true
      name   = "external-secrets"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.eso_irsa.role_arn
      }
    }

    # Scrape-ready metrics; Phase 5 adds the ServiceMonitor/alerts.
    metrics = {
      service = { enabled = true }
    }
  })]

  # The ALB controller's mutating webhook intercepts every Service creation.
  # Installing it first avoids "no endpoints available for service" races.
  depends_on = [helm_release.alb_controller]
}

# -----------------------------------------------------------------------------
# ArgoCD
# -----------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  atomic  = true
  timeout = 900

  values = [yamlencode({
    configs = {
      params = {
        # TLS is terminated outside the pod (port-forward in dev, ALB + ACM if
        # you later expose it), so the server speaks plain HTTP internally.
        "server.insecure" = true
      }
      cm = {
        # Track resources with annotations instead of labels: avoids clashes
        # with Helm-managed `app.kubernetes.io/instance` labels.
        "application.resourceTrackingMethod" = "annotation"
        # Poll Git every 3 min as a safety net; webhooks make it instant.
        "timeout.reconciliation" = "180s"
      }
    }

    controller = {
      replicas = 1 # the application controller is sharded, not HA-replicated
    }

    server = {
      replicas = local.replicas
    }

    repoServer = {
      replicas = local.replicas
    }

    applicationSet = {
      replicas = local.replicas
    }

    dex           = { enabled = false } # SSO off; add OIDC later
    notifications = { enabled = false }
  })]

  depends_on = [helm_release.alb_controller]
}
