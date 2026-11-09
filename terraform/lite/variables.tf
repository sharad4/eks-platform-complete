variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "eks-platform-lite"
}

variable "instance_type" {
  description = <<-EOT
    MUST be eligible for YOUR account's free plan. Check with:
      aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
        --query 'InstanceTypes[].InstanceType' --output text
    Accounts created on/after 2025-07-15 (free plan): t3.micro/small, t4g.micro/small,
    c7i-flex.large, m7i-flex.large. Older accounts (12-month free tier): t2/t3.micro.
    The platform needs ~2.5 GB RAM: use a 4 GB type (c7i-flex.large) if you can;
    a 2 GB type (t3.small, t4g.small) works with swap and no monitoring; 1 GB does not.
  EOT
  type        = string
  default     = "c7i-flex.large"
}

variable "root_volume_gb" {
  description = "Root disk (gp3). The free tier covers 30 GB of EBS."
  type        = number
  default     = 30
}

variable "swap_gb" {
  description = "Swap file size. Cheap insurance on small instances; 0 disables."
  type        = number
  default     = 2
}

variable "http_cidrs" {
  description = "Who may reach HTTP(S) on the instance. Narrow this to your IP for a private demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "github_org" {
  description = "GitHub org/user that owns the (public) repo."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "repo_branch" {
  type    = string
  default = "main"
}

variable "k3s_version" {
  description = "Pin a k3s release (e.g. v1.33.4+k3s1). Empty = latest stable channel."
  type        = string
  default     = ""
}

variable "argocd_version" {
  description = "Argo CD git ref for the install manifests. 'stable' or a tag like v2.14.11 (pin a tag for repeatability)."
  type        = string
  default     = "stable"
}

variable "argocd_mode" {
  description = "core (no UI, lightest) or full."
  type        = string
  default     = "core"
  validation {
    condition     = contains(["core", "full"], var.argocd_mode)
    error_message = "argocd_mode must be core or full."
  }
}

variable "budget_email" {
  description = "If set, creates a $5/month AWS Budget that emails this address at 80% actual and 100% forecast. Strongly recommended."
  type        = string
  default     = ""
}

variable "budget_limit_usd" {
  type    = number
  default = 5
}
