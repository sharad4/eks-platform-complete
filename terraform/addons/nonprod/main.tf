# =============================================================================
# Platform add-ons for the NON-PROD cluster.
#
# WHY A SEPARATE STATE FROM ../../environments/nonprod?
# The Helm provider must connect to the cluster at PLAN time. If the cluster is
# created in the same apply, the provider has nothing to connect to on a fresh
# run ("chicken and egg"). Splitting into layers fixes this and also gives a
# smaller blast radius: re-applying add-ons can never touch the VPC or database.
#
#   layer 1: environments/nonprod  (VPC, EKS, RDS, ...)   <- apply first
#   layer 2: addons/nonprod        (controllers via Helm) <- this stack
# =============================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "nonprod"
      ManagedBy   = "terraform"
      Layer       = "addons"
    }
  }
}

# Read layer 1's outputs instead of duplicating values.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.infra_state_key
    region = var.region
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.infra.outputs.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    # Short-lived token fetched on demand; nothing stored in state or on disk.
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.this.name, "--region", var.region]
    }
  }
}

module "addons" {
  source = "../../modules/platform-addons"

  cluster_name         = data.aws_eks_cluster.this.name
  region               = var.region
  vpc_id               = data.terraform_remote_state.infra.outputs.vpc_id
  oidc_provider_arn    = data.terraform_remote_state.infra.outputs.oidc_provider_arn
  oidc_provider_url    = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  eso_read_policy_json = data.terraform_remote_state.infra.outputs.eso_read_policy_json

  high_availability = false
}
