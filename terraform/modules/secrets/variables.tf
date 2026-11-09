variable "name" {
  description = "Secret path prefix, e.g. nonprod/dev. Becomes <name>/backend."
  type        = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "redis_host" {
  type = string
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "redis_auth_token" {
  type      = string
  sensitive = true
}

variable "extra_secret_arns" {
  description = "Additional secret ARNs the reader policy should cover (e.g. the RDS-managed master secret)."
  type        = list(string)
  default     = []
}

variable "kms_key_id" {
  description = "Customer-managed KMS key for the secret. Null uses the AWS-managed aws/secretsmanager key."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Deletion grace period (0 = immediate, dev only)."
  type        = number
  default     = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
