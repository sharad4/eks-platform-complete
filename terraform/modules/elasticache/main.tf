# =============================================================================
# ElastiCache Redis module (replication group)
#
#   * Encrypted at rest and in transit (TLS) + AUTH token
#   * Automatic failover + Multi-AZ when num_cache_clusters > 1
#   * Isolated data subnets, ingress only from the EKS SG on 6379
#
# Laravel note: with transit encryption on, use the `tls://` scheme / REDIS_SCHEME=tls.
# =============================================================================

locals {
  tags = merge(var.tags, { Module = "elasticache" })
  ha   = var.num_cache_clusters > 1
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.data_subnet_ids
  tags       = local.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "Redis access from EKS workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-redis" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_eks" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis from EKS"
}

# AUTH token: generated here, stored in state (encrypted bucket) and handed to
# the secrets module, which publishes it to Secrets Manager for External Secrets.
# ElastiCache tokens may not contain @ " / so special chars are disabled.
resource "random_password" "auth" {
  length  = 40
  special = false
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "Redis for ${var.name}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.ha
  multi_az_enabled           = local.ha

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth.result

  snapshot_retention_limit   = var.snapshot_retention_days
  snapshot_window            = "19:00-20:00"
  maintenance_window         = "sun:20:30-sun:21:30"
  auto_minor_version_upgrade = true
  apply_immediately          = false

  tags = merge(local.tags, { Name = var.name })
}
