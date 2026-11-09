variable "name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes minor version. Check `aws eks describe-cluster-versions` and pick one comfortably inside standard support: extended support costs 6x more per cluster-hour."
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets for the control-plane ENIs and the worker nodes."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API publicly (restricted by public_access_cidrs). Set false for fully private clusters reached via VPN/bastion."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. NEVER leave 0.0.0.0/0 in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "Extra IAM principals (roles/users) granted cluster-admin via EKS access entries. Do NOT list the identity running terraform: it already gets an entry from bootstrap_cluster_creator_admin_permissions, and a duplicate fails with ResourceInUseException."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Retention for control-plane logs in CloudWatch."
  type        = number
  default     = 30
}

variable "node_groups" {
  description = "Managed node groups keyed by name."
  type = map(object({
    instance_types = list(string)
    capacity_type  = optional(string, "ON_DEMAND") # ON_DEMAND | SPOT
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = optional(number, 50)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string # NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE
    })), [])
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}
