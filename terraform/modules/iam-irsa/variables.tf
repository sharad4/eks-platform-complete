variable "name" {
  description = "IAM role name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (eks module output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL of the cluster's OIDC provider (eks module output)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account allowed to assume this role."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name allowed to assume this role."
  type        = string
}

variable "policy_json" {
  description = "Inline least-privilege policy document (JSON). Null to skip."
  type        = string
  default     = null
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
