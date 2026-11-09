variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "force_destroy" {
  description = "Allow destroy with objects inside (dev only)."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
