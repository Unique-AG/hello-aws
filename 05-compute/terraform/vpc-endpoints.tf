#######################################
# VPC Endpoints for Compute Services
#######################################
#
# VPC endpoints for compute services (EKS)
# These enable private access to AWS services from within the VPC without internet access
#
# Note: These endpoints use the VPC and security groups from the infrastructure layer
# via remote state references
#######################################

# EKS Interface Endpoint
# Required for EKS API access from private subnets when EKS is deployed as internal-only service
# This endpoint allows kubectl and EKS API calls from within the VPC without internet access
resource "aws_vpc_endpoint" "eks" {
  count = var.enable_eks_endpoint ? 1 : 0

  vpc_id              = local.infrastructure.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.eks"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.infrastructure.private_subnet_ids
  security_group_ids  = [local.infrastructure.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-eks"
  }
}

