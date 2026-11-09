variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "public_access_cidrs" {
  description = "REQUIRED: no default on purpose. Production API access must be an explicit decision (VPN/office egress IPs)."
  type        = list(string)

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed for the production Kubernetes API endpoint."
  }
}

variable "admin_principal_arns" {
  type    = list(string)
  default = []
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.small"
}
