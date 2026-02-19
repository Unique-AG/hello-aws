# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "subnet-group-${module.naming.id}-redis"
  subnet_ids = local.infrastructure.isolated_subnet_ids

  tags = {
    Name    = "subnet-group-${module.naming.id}-redis"
    Purpose = "redis-subnet-group"
  }
}

# Security Group for ElastiCache
resource "aws_security_group" "elasticache" {
  name        = "${module.naming.id}-elasticache"
  description = "Security group for ElastiCache Redis cluster"
  vpc_id      = local.infrastructure.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name    = "sg-${module.naming.id}-elasticache"
    Purpose = "elasticache-security-group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "elasticache_from_private_subnets" {
  for_each = toset(local.infrastructure.private_subnet_cidrs)

  security_group_id = aws_security_group.elasticache.id
  description       = "Redis TLS from private subnet (${each.value})"
  from_port         = 6380
  to_port           = 6380
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "elasticache_to_vpc" {
  security_group_id = aws_security_group.elasticache.id
  description       = "Allow outbound to VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = data.aws_vpc.main.cidr_block
}

# ElastiCache Redis Replication Group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "redis-${module.naming.id}"
  description          = "Redis cluster for ${var.environment} environment"
  engine               = "redis"
  engine_version       = var.elasticache_engine_version
  node_type            = var.elasticache_node_type
  num_cache_clusters   = var.elasticache_num_cache_nodes
  # Port 6380 triggers auto-TLS in Node.js chat service (see pubSub.base.ts:42)
  port                 = 6380
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.elasticache.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = local.infrastructure.kms_key_general_arn
  apply_immediately          = true

  automatic_failover_enabled = var.elasticache_automatic_failover_enabled
  multi_az_enabled           = var.elasticache_multi_az_enabled
  snapshot_retention_limit   = var.elasticache_snapshot_retention_limit
  snapshot_window            = var.elasticache_snapshot_window
  maintenance_window         = var.elasticache_maintenance_window

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.elasticache.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = {
    Name    = "redis-${module.naming.id}"
    Purpose = "redis-cache"
  }
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "redis" {
  name   = "param-group-${module.naming.id}-redis"
  family = var.elasticache_parameter_family

  tags = {
    Name    = "param-group-${module.naming.id}-redis"
    Purpose = "redis-parameter-group"
  }
}

# CloudWatch Log Group for ElastiCache
resource "aws_cloudwatch_log_group" "elasticache" {
  name              = "${module.naming.log_group_prefix}/elasticache"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = local.infrastructure.kms_key_cloudwatch_logs_arn

  tags = {
    Name    = "log-${module.naming.id}-elasticache"
    Purpose = "elasticache-logs"
  }
}
