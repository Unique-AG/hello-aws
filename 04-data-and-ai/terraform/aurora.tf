#######################################
# Aurora PostgreSQL
#######################################
#
# Amazon Aurora PostgreSQL cluster with:
# - Multi-AZ deployment in isolated subnets
# - KMS encryption using infrastructure layer key
# - Private access only (no public endpoint)
# - Automated backups
# - Access via VPC endpoints (no internet required)
#######################################

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "subnet-group-${module.naming.id}-aurora"
  subnet_ids = local.infrastructure.isolated_subnet_ids

  tags = merge(
    local.tags,
    {
      Name    = "subnet-group-${module.naming.id}-aurora"
      Purpose = "aurora-subnet-group"
    }
  )
}

# VPC data source for CIDR block
data "aws_vpc" "main" {
  id = local.infrastructure.vpc_id
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name        = "${module.naming.id}-aurora"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = local.infrastructure.vpc_id

  ingress {
    description     = "PostgreSQL from private subnets"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = [data.aws_vpc.main.cidr_block]
    security_groups = [] # Can be updated to allow specific security groups
  }

  # Aurora instances don't need outbound internet access
  # They only communicate within the VPC
  egress {
    description = "Allow outbound to VPC for database operations"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  tags = merge(
    local.tags,
    {
      Name    = "sg-${module.naming.id}-aurora"
      Purpose = "aurora-security-group"
    }
  )
}

# Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "postgres" {
  cluster_identifier           = "aurora-${module.naming.id}-postgres"
  engine                       = "aurora-postgresql"
  engine_version               = var.aurora_engine_version
  database_name                = var.aurora_database_name
  master_username              = random_password.postgres_username.result
  master_password              = random_password.postgres_password.result
  backup_retention_period      = var.aurora_backup_retention_period
  preferred_backup_window      = var.aurora_preferred_backup_window
  preferred_maintenance_window = var.aurora_preferred_maintenance_window

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  # Encryption
  storage_encrypted = true
  kms_key_id        = local.infrastructure.kms_key_general_arn

  # High Availability
  enabled_cloudwatch_logs_exports = ["postgresql"]
  deletion_protection             = var.aurora_deletion_protection
  skip_final_snapshot             = var.aurora_skip_final_snapshot

  # Performance
  engine_mode = "provisioned"

  tags = merge(
    local.tags,
    {
      Name    = "aurora-${module.naming.id}-postgres"
      Purpose = "postgresql-database"
    }
  )
}

# Aurora PostgreSQL Cluster Instances
resource "aws_rds_cluster_instance" "postgres" {
  count              = var.aurora_instance_count
  identifier         = "aurora-${module.naming.id}-postgres-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.postgres.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.postgres.engine
  engine_version     = aws_rds_cluster.postgres.engine_version

  # Performance Insights
  performance_insights_enabled    = var.aurora_performance_insights_enabled
  performance_insights_kms_key_id = var.aurora_performance_insights_enabled ? local.infrastructure.kms_key_general_arn : null

  tags = merge(
    local.tags,
    {
      Name    = "aurora-${module.naming.id}-postgres-${count.index + 1}"
      Purpose = "postgresql-instance"
    }
  )
}

