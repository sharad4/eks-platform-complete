variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  description = "Required by the ALB controller (it cannot always auto-discover it)."
  type        = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "eso_read_policy_json" {
  description = "Least-privilege Secrets Manager read policy for External Secrets (from the environment stack output)."
  type        = string
}

variable "high_availability" {
  description = "Run 2 replicas of controllers (prod) instead of 1 (non-prod, saves memory)."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Chart versions. PIN THEM: an unpinned add-on is an unreviewed production change.
# These were chosen from knowledge, NOT verified against the live repos at
# authoring time. Before the first apply, check and bump deliberately:
#   helm repo add eks https://aws.github.io/eks-charts
#   helm search repo eks/aws-load-balancer-controller --versions | head
# and likewise for external-secrets, argo/argo-cd, metrics-server.
# If you bump the ALB controller chart, bump alb_controller_policy_ref to the
# matching app version tag so the IAM policy matches the controller's needs.
# -----------------------------------------------------------------------------
variable "alb_controller_chart_version" {
  type    = string
  default = "1.13.0"
}

variable "alb_controller_policy_ref" {
  description = "Git tag of kubernetes-sigs/aws-load-balancer-controller whose docs/install/iam_policy.json is used. Match the chart's appVersion."
  type        = string
  default     = "v2.13.0"
}

variable "external_secrets_chart_version" {
  type    = string
  default = "0.18.2"
}

variable "argocd_chart_version" {
  type    = string
  default = "8.0.0"
}

variable "metrics_server_chart_version" {
  type    = string
  default = "3.12.2"
}

variable "tags" {
  type    = map(string)
  default = {}
}
