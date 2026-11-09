# =============================================================================
# NON-PROD stack: one EKS cluster hosting `dev` and `staging` namespaces.
#
# Environments are structurally identical to prod (same modules); only inputs
# differ. Each logical environment gets its OWN database, Redis, bucket, secret
# and IRSA role, so a bad migration in dev can never touch staging data.
# =============================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "nonprod"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name         = "${var.project}-nonprod"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  account_id   = data.aws_caller_identity.current.account_id
  environments = var.environments
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name         = local.name
  cidr         = var.vpc_cidr
  azs          = local.azs
  cluster_name = local.name

  # Cost trade-off: one NAT for non-prod (~$33/mo vs ~$100/mo for three).
  # Downside: if that AZ fails, nodes in other AZs lose outbound internet.
  single_nat_gateway = true
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  name                 = local.name
  cluster_version      = var.cluster_version
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  public_access_cidrs  = var.public_access_cidrs
  admin_principal_arns = var.admin_principal_arns

  node_groups = {
    # Small, always-on capacity for cluster add-ons (ArgoCD, controllers).
    system = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      labels         = { "workload" = "system" }
    }

    # Cheap Spot capacity for stateless app pods. Multiple instance types
    # widen the Spot pools -> fewer interruptions.
    apps = {
      instance_types = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
      capacity_type  = "SPOT"
      min_size       = 2
      max_size       = 6
      desired_size   = 2
      labels         = { "workload" = "apps" }
    }
  }
}

# -----------------------------------------------------------------------------
# Container registry (shared by every environment; images are promoted by tag)
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  prefix       = var.project
  repositories = ["backend", "frontend"]
  force_delete = true # non-prod convenience; prod keeps this false
}

# -----------------------------------------------------------------------------
# Per-environment data services
# -----------------------------------------------------------------------------
module "rds" {
  source   = "../../modules/rds"
  for_each = local.environments

  name                       = "${var.project}-${each.key}"
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  instance_class               = each.value.rds_instance_class
  performance_insights_enabled = false # unsupported on t4g.micro/small
  multi_az                     = false # cost trade-off for non-prod
  backup_retention_days = 3
  deletion_protection   = false
  skip_final_snapshot   = true # throwaway data
}

module "redis" {
  source   = "../../modules/elasticache"
  for_each = local.environments

  name                       = "${var.project}-${each.key}"
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  node_type          = each.value.redis_node_type
  num_cache_clusters = 1
}

module "secrets" {
  source   = "../../modules/secrets"
  for_each = local.environments

  name = "nonprod/${each.key}"

  db_host          = module.rds[each.key].address
  db_port          = module.rds[each.key].port
  db_name          = module.rds[each.key].db_name
  redis_host       = module.redis[each.key].primary_endpoint
  redis_port       = module.redis[each.key].port
  redis_auth_token = module.redis[each.key].auth_token

  extra_secret_arns       = [module.rds[each.key].master_user_secret_arn]
  recovery_window_in_days = 0 # immediate delete so destroy/recreate cycles work
}

module "uploads" {
  source   = "../../modules/s3"
  for_each = local.environments

  bucket_name   = "${var.project}-${each.key}-uploads-${local.account_id}"
  force_destroy = true
}

# -----------------------------------------------------------------------------
# IRSA: one least-privilege role per environment for the backend service account
# The namespace in the trust policy means dev's role cannot be used by staging.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "backend" {
  for_each = local.environments

  statement {
    sid       = "ObjectAccess"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.uploads[each.key].bucket_arn}/*"]
  }

  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [module.uploads[each.key].bucket_arn]
  }
}

module "backend_irsa" {
  source   = "../../modules/iam-irsa"
  for_each = local.environments

  name              = "${var.project}-${each.key}-backend"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = each.key # namespace == environment name
  service_account   = "backend"
  policy_json       = data.aws_iam_policy_document.backend[each.key].json
}
