variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "state_bucket" {
  type = string
}

variable "infra_state_key" {
  type    = string
  default = "prod/terraform.tfstate"
}
