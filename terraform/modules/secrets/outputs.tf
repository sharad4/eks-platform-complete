output "secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "secret_name" {
  description = "Use as remoteRef.key in the ExternalSecret."
  value       = aws_secretsmanager_secret.app.name
}

output "read_policy_json" {
  description = "Least-privilege policy for the External Secrets IRSA role."
  value       = data.aws_iam_policy_document.read.json
}
