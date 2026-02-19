# VPC data source for CIDR-based security group rules
data "aws_vpc" "main" {
  id = local.infrastructure.vpc_id
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "subnet-group-${module.naming.id}-aurora"
  subnet_ids = local.infrastructure.isolated_subnet_ids

  tags = {
    Name    = "subnet-group-${module.naming.id}-aurora"
    Purpose = "aurora-subnet-group"
  }
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name        = "${module.naming.id}-aurora"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = local.infrastructure.vpc_id

  tags = {
    Name    = "sg-${module.naming.id}-aurora"
    Purpose = "aurora-security-group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_private_subnets" {
  for_each = toset(local.infrastructure.private_subnet_cidrs)

  security_group_id = aws_security_group.aurora.id
  description       = "PostgreSQL from private subnet (${each.value})"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "aurora_to_vpc" {
  security_group_id = aws_security_group.aurora.id
  description       = "Allow outbound to VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = data.aws_vpc.main.cidr_block
}

# Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "postgres" {
  cluster_identifier            = "aurora-${module.naming.id}-postgres"
  engine                        = "aurora-postgresql"
  engine_version                = var.aurora_engine_version
  database_name                 = var.aurora_database_name
  master_username               = "dbadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.infrastructure.kms_key_secrets_manager_arn
  backup_retention_period       = var.aurora_backup_retention_period
  preferred_backup_window       = var.aurora_preferred_backup_window
  preferred_maintenance_window  = var.aurora_preferred_maintenance_window

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  storage_encrypted               = true
  kms_key_id                      = local.infrastructure.kms_key_general_arn
  enabled_cloudwatch_logs_exports = ["postgresql"]
  deletion_protection             = var.aurora_deletion_protection
  skip_final_snapshot             = var.aurora_skip_final_snapshot
  final_snapshot_identifier       = var.aurora_skip_final_snapshot ? null : "aurora-${module.naming.id}-postgres-final"
  engine_mode                     = "provisioned"

  tags = {
    Name    = "aurora-${module.naming.id}-postgres"
    Purpose = "postgresql-database"
  }
}

# Aurora PostgreSQL Cluster Instances
resource "aws_rds_cluster_instance" "postgres" {
  count              = var.aurora_instance_count
  identifier         = "aurora-${module.naming.id}-postgres-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.postgres.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.postgres.engine
  engine_version     = aws_rds_cluster.postgres.engine_version

  performance_insights_enabled    = var.aurora_performance_insights_enabled
  performance_insights_kms_key_id = var.aurora_performance_insights_enabled ? local.infrastructure.kms_key_general_arn : null

  tags = {
    Name    = "aurora-${module.naming.id}-postgres-${count.index + 1}"
    Purpose = "postgresql-instance"
  }
}
