variable "prefix" {
  description = "Repository namespace, e.g. eks-platform -> eks-platform/backend. Must match the CI role's ECR resource ARN in bootstrap."
  type        = string
}

variable "repositories" {
  description = "Repository names to create."
  type        = list(string)
  default     = ["backend", "frontend"]
}

variable "keep_last" {
  description = "How many images to retain per repository."
  type        = number
  default     = 30
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repos that still contain images (dev only)."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
