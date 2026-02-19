# Aurora Interface Endpoint
# Aurora is managed via the RDS API — this endpoint enables SDK calls from within the VPC
resource "aws_vpc_endpoint" "aurora" {
  count = var.enable_aurora_endpoint ? 1 : 0

  vpc_id              = local.infrastructure.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.rds"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.infrastructure.private_subnet_ids
  security_group_ids  = [data.terraform_remote_state.infrastructure.outputs.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-aurora"
  }
}

# ElastiCache Interface Endpoint
# Enables SDK calls to ElastiCache API from within the VPC
resource "aws_vpc_endpoint" "elasticache" {
  count = var.enable_elasticache_endpoint ? 1 : 0

  vpc_id              = local.infrastructure.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.elasticache"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.infrastructure.private_subnet_ids
  security_group_ids  = [data.terraform_remote_state.infrastructure.outputs.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-elasticache"
  }
}
