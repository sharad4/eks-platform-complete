output "address" {
  description = "DB hostname (no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the auto-rotated master credentials (JSON: username/password). External Secrets reads this."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  description = "CMK encrypting storage and the managed master secret. Readers of that secret need kms:Decrypt on it."
  value       = aws_kms_key.this.arn
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "instance_arn" {
  value = aws_db_instance.this.arn
}
