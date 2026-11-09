output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "backend_irsa_role_arns" {
  description = "Annotate each env's backend ServiceAccount with its role ARN (Helm values in Phase 3)."
  value       = { for k, m in module.backend_irsa : k => m.role_arn }
}

output "app_secret_names" {
  description = "Secrets Manager keys referenced by ExternalSecrets."
  value       = { for k, m in module.secrets : k => m.secret_name }
}

output "db_master_secret_arns" {
  value = { for k, m in module.rds : k => m.master_user_secret_arn }
}

# Consumed by the platform add-ons in Phase 3 (External Secrets IRSA policy).
output "eso_read_policy_json" {
  description = "Union of the per-environment secret read policies."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = concat(
          [for m in module.secrets : m.secret_arn],
          [for m in module.rds : m.master_user_secret_arn],
          ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:platform/*"],
        )
      },
      {
        # The RDS-managed master secret is encrypted with the RDS CMK.
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [for m in module.rds : m.kms_key_arn]
      }
    ]
  })
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
