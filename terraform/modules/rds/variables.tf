variable "name" {
  description = "DB instance identifier and name prefix."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "data_subnet_ids" {
  description = "Isolated data-tier subnets (no internet route)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on 5432 (the EKS node/cluster SG)."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL version. A bare major (\"16\") lets RDS pick the current default minor; old minors get retired, so pinning one rots. Minor upgrades are applied automatically."
  type        = string
  default     = "16"
}

variable "performance_insights_enabled" {
  description = "Not supported on db.t4g.micro/small, so disable for those classes."
  type        = bool
  default     = true
}

variable "instance_class" {
  description = "Graviton (t4g/m7g) is ~20% cheaper than x86 equivalents."
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB. Set equal to allocated_storage to disable."
  type        = number
  default     = 100
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "username" {
  type    = string
  default = "app_admin"
}

variable "multi_az" {
  description = "Synchronous standby in another AZ. Doubles instance cost; required for production."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention (point-in-time recovery window). Max 35."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  description = "true only for throwaway environments."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
