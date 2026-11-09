# =============================================================================
# RDS PostgreSQL module
#
# Production-minded defaults:
#   * Lives in isolated data subnets; reachable only from the EKS SG on 5432
#   * Encrypted at rest with a customer-managed KMS key
#   * TLS enforced (rds.force_ssl)
#   * Master password is generated AND rotated by RDS in Secrets Manager
#     (manage_master_user_password) -> the password never exists in Terraform
#     state, code or CI logs
#   * Automated backups + PITR, final snapshot, deletion protection
#   * Performance Insights + Enhanced Monitoring
# =============================================================================

locals {
  tags = merge(var.tags, { Module = "rds" })
}

resource "aws_kms_key" "this" {
  description             = "RDS ${var.name} storage + secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.data_subnet_ids
  tags       = merge(local.tags, { Name = var.name })
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "PostgreSQL access from EKS workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-rds" })

  # Replacing an SG that is in use fails; create the new one first.
  lifecycle {
    create_before_destroy = true
  }
}

# Separate rule resources (not inline) so adding/removing a source never
# forces SG replacement.
resource "aws_vpc_security_group_ingress_rule" "from_eks" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS"
}

# No egress rules: a database has no reason to initiate outbound connections.

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg16-"
  family      = "postgres16"
  description = "Hardened + observable PostgreSQL 16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500 ms
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced Monitoring role (OS-level metrics every 60 s)
data "aws_iam_policy_document" "monitoring_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier = var.name

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username

  # RDS creates and rotates the master password in Secrets Manager.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  # Backups: daily snapshot + transaction logs => restore to any second
  # inside the retention window (RPO ~5 min).
  backup_retention_period   = var.backup_retention_days
  backup_window             = "20:00-21:00" # UTC; pick your quietest hour
  maintenance_window        = "sun:21:30-sun:22:30"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  auto_minor_version_upgrade = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.this.arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  tags = merge(local.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [engine_version] # minor upgrades are applied by RDS itself
  }
}
