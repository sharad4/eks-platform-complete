output "primary_endpoint" {
  description = "Write endpoint (follows the primary through failovers)."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  value = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  value = 6379
}

output "auth_token" {
  description = "Redis AUTH token. Consumed by the secrets module only."
  value       = random_password.auth.result
  sensitive   = true
}

output "security_group_id" {
  value = aws_security_group.this.id
}
