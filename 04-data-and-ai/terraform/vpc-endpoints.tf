#######################################
# VPC Endpoints for Data and AI Services
#######################################
#
# VPC endpoints for data and AI services required by EKS pods
# These enable private access to AWS services from pods without internet access
#
# Note: These endpoints use the VPC and security groups from the infrastructure layer
# via remote state references
#######################################

# RDS Interface Endpoint
# Required for RDS API operations (cluster management, parameter groups, etc.)
# Note: Pods connect directly to RDS cluster endpoints (private IPs), but AWS SDK calls need this endpoint
resource "aws_vpc_endpoint" "rds" {
  count = var.enable_rds_endpoint ? 1 : 0

  vpc_id              = local.infrastructure.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.rds"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.infrastructure.private_subnet_ids
  security_group_ids  = [data.terraform_remote_state.infrastructure.outputs.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-rds"
    }
  )
}

# ElastiCache Interface Endpoint
# Required for ElastiCache API operations (cluster management, parameter groups, etc.)
# Note: Pods connect directly to ElastiCache cluster endpoints (private IPs), but AWS SDK calls need this endpoint
resource "aws_vpc_endpoint" "elasticache" {
  count = var.enable_elasticache_endpoint ? 1 : 0

  vpc_id              = local.infrastructure.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.elasticache"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.infrastructure.private_subnet_ids
  security_group_ids  = [data.terraform_remote_state.infrastructure.outputs.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-elasticache"
    }
  )
}

