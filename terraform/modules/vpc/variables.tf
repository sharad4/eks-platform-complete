variable "name" {
  description = "Name prefix for all VPC resources."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block. Must be a /16 so the subnet maths in main.tf works."
  type        = string
}

variable "azs" {
  description = "Availability zones to span (2 minimum, 3 for production)."
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name. Used to tag subnets so the ALB controller and Karpenter can discover them."
  type        = string
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, single-AZ failure domain). false = one NAT per AZ (production)."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch retention for VPC flow logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
