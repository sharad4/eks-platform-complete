# =============================================================================
# IRSA role factory
#
# Creates an IAM role that ONLY a specific Kubernetes ServiceAccount can assume.
# The trust policy pins the OIDC `sub` claim to
#   system:serviceaccount:<namespace>:<serviceaccount>
# so a compromised pod elsewhere in the cluster cannot reuse the role.
#
# Usage:
#   module "backend_irsa" {
#     source            = "../../modules/iam-irsa"
#     name              = "dev-backend"
#     oidc_provider_arn = module.eks.oidc_provider_arn
#     oidc_provider_url = module.eks.oidc_provider_url
#     namespace         = "dev"
#     service_account   = "backend"
#     policy_json       = data.aws_iam_policy_document.backend.json
#   }
# =============================================================================

locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "inline" {
  count = var.policy_json == null ? 0 : 1

  name   = "${var.name}-inline"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
