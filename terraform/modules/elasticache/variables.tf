variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "data_subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on 6379."
  type        = list(string)
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  description = "Graviton cache.t4g.* / cache.m7g.* are cheapest per GiB."
  type        = string
  default     = "cache.t4g.small"
}

variable "num_cache_clusters" {
  description = "Total nodes (1 primary + N-1 replicas). >1 enables Multi-AZ automatic failover."
  type        = number
  default     = 1
}

variable "snapshot_retention_days" {
  type    = number
  default = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
