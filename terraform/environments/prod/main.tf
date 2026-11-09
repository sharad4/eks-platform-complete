# =============================================================================
# PRODUCTION stack: dedicated cluster, 3 AZs, HA data tier.
#
# Compare with ../nonprod/main.tf: same modules, different inputs. That is the
# whole point of modules, and why prod and non-prod behave alike.
#
# Differences, each a deliberate decision:
#   * 3 AZs and one NAT gateway per AZ (no cross-AZ egress dependency)
#   * ON_DEMAND nodes only for the core pool (Spot interruptions are acceptable
#     for stateless burst capacity, not for the baseline)
#   * RDS Multi-AZ, 14-day PITR, deletion protection, final snapshot
#   * Redis with a replica + automatic failover
#   * Secrets keep a 7-day recovery window
#   * ECR is NOT created here: images are built once and PROMOTED from the
#     non-prod registry (same account, so the node role's ECR read access works).
# =============================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name       = "${var.project}-prod"
  azs        = slice(data.aws_availability_zones.available.names, 0, 3)
  account_id = data.aws_caller_identity.current.account_id
  namespace  = "production"
}

module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cidr         = var.vpc_cidr
  azs          = local.azs
  cluster_name = local.name

  single_nat_gateway       = false # one NAT per AZ
  flow_logs_retention_days = 90
}

module "eks" {
  source = "../../modules/eks"

  name                 = local.name
  cluster_version      = var.cluster_version
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  public_access_cidrs  = var.public_access_cidrs
  admin_principal_arns = var.admin_principal_arns
  log_retention_days   = 90

  node_groups = {
    # Baseline capacity: on-demand, spread over 3 AZs (min 3 = 1 per AZ).
    core = {
      instance_types = ["m6i.large"]
      capacity_type  = "ON_DEMAND"
      min_size       = 3
      max_size       = 9
      desired_size   = 3
      labels         = { "workload" = "core" }
    }

    # Optional burst capacity on Spot for stateless pods that tolerate eviction.
    # Tainted so only workloads that explicitly opt in land here.
    burst = {
      instance_types = ["m6i.large", "m5.large", "m6a.large", "m5a.large"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 6
      desired_size   = 0
      labels         = { "workload" = "burst" }
      taints = [{
        key    = "capacity"
        value  = "spot"
        effect = "NO_SCHEDULE"
      }]
    }
  }
}

module "rds" {
  source = "../../modules/rds"

  name                       = "${var.project}-production"
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  instance_class        = var.rds_instance_class
  allocated_storage     = 50
  max_allocated_storage = 500
  multi_az              = true
  backup_retention_days = 14
  deletion_protection   = true
  skip_final_snapshot   = false
}

module "redis" {
  source = "../../modules/elasticache"

  name                       = "${var.project}-production"
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  node_type               = var.redis_node_type
  num_cache_clusters      = 2 # primary + replica in a different AZ
  snapshot_retention_days = 7
}

module "secrets" {
  source = "../../modules/secrets"

  name = "prod/production"

  db_host          = module.rds.address
  db_port          = module.rds.port
  db_name          = module.rds.db_name
  redis_host       = module.redis.primary_endpoint
  redis_port       = module.redis.port
  redis_auth_token = module.redis.auth_token

  extra_secret_arns       = [module.rds.master_user_secret_arn]
  recovery_window_in_days = 7
}

module "uploads" {
  source = "../../modules/s3"

  bucket_name   = "${var.project}-production-uploads-${local.account_id}"
  force_destroy = false
}

data "aws_iam_policy_document" "backend" {
  statement {
    sid       = "ObjectAccess"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.uploads.bucket_arn}/*"]
  }

  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [module.uploads.bucket_arn]
  }
}

module "backend_irsa" {
  source = "../../modules/iam-irsa"

  name              = "${var.project}-production-backend"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = local.namespace
  service_account   = "backend"
  policy_json       = data.aws_iam_policy_document.backend.json
}
