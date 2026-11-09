output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "backend_irsa_role_arn" {
  value = module.backend_irsa.role_arn
}

output "app_secret_name" {
  value = module.secrets.secret_name
}

output "db_master_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "eso_read_policy_json" {
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [module.secrets.secret_arn, module.rds.master_user_secret_arn, "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:platform/*"]
      },
      {
        # The RDS-managed master secret is encrypted with the RDS CMK.
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.rds.kms_key_arn]
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
