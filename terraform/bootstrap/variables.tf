variable "region" {
  description = "AWS region for the state bucket, lock table and OIDC roles."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project slug used as a prefix for every resource name."
  type        = string
  default     = "eks-platform"
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org)."
  type        = string
}

variable "apply_environments" {
  description = "GitHub Environments allowed to assume the Terraform apply role. Each should have required reviewers configured."
  type        = list(string)
  default     = ["nonprod-infra", "production-infra"]
}
