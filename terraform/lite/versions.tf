terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 7.0"
    }
  }
  # Local state on purpose: this stack is a throwaway single VM. Keep the
  # terraform.tfstate file (gitignored) or you lose track of what to destroy.
}
