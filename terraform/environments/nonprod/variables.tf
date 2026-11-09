variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "vpc_cidr" {
  description = "Must not overlap prod (10.20.0.0/16) if you ever peer them."
  type        = string
  default     = "10.10.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (your office/VPN/home IP as x.x.x.x/32)."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "IAM role/user ARNs that get cluster-admin."
  type        = list(string)
  default     = []
}

variable "environments" {
  description = "Logical environments sharing this cluster. Each gets its own namespace, database, Redis, bucket and secrets."
  type = map(object({
    rds_instance_class = string
    redis_node_type    = string
  }))

  default = {
    dev = {
      rds_instance_class = "db.t4g.micro"
      redis_node_type    = "cache.t4g.micro"
    }
    staging = {
      rds_instance_class = "db.t4g.small"
      redis_node_type    = "cache.t4g.small"
    }
  }
}
