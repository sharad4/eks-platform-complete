variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "state_bucket" {
  description = "State bucket from the bootstrap output."
  type        = string
}

variable "infra_state_key" {
  description = "State key used by terraform/environments/nonprod."
  type        = string
  default     = "nonprod/terraform.tfstate"
}
