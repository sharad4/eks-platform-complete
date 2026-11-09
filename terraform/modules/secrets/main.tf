# =============================================================================
# Application secrets in AWS Secrets Manager
#
# This is the SOURCE side of the External Secrets flow:
#
#   Terraform -> Secrets Manager -> External Secrets Operator (IRSA) -> K8s Secret
#
# Nothing sensitive is ever committed to Git. The Kubernetes manifests only
# contain *references* ("fetch key X"), which are safe to publish.
#
# The database master password is NOT here: RDS owns and rotates it (see rds
# module output master_user_secret_arn). Non-secret connection facts (host,
# port, db name) are stored alongside for convenience so one ExternalSecret can
# pull the whole bundle.
# =============================================================================

resource "random_id" "app_key" {
  byte_length = 32 # Laravel expects a 32-byte key, base64-encoded
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.name}/backend"
  description             = "Backend runtime configuration for ${var.name}"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    APP_KEY        = "base64:${random_id.app_key.b64_std}"
    DB_HOST        = var.db_host
    DB_PORT        = tostring(var.db_port)
    DB_DATABASE    = var.db_name
    REDIS_HOST     = var.redis_host
    REDIS_PORT     = tostring(var.redis_port)
    REDIS_PASSWORD = var.redis_auth_token
  })
}

# Least-privilege read policy for External Secrets Operator. Attach it to the
# ESO IRSA role (Phase 3) so ESO can read ONLY this environment's secrets.
data "aws_iam_policy_document" "read" {
  statement {
    sid       = "ReadAppSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat([aws_secretsmanager_secret.app.arn], var.extra_secret_arns)
  }
}
