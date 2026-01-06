#######################################
# VPC Endpoints
#######################################
#
# VPC endpoints provide private connectivity to AWS services
# without requiring internet access or NAT Gateway.
#
# Gateway Endpoints (S3, DynamoDB):
# - Free, no security groups, route table based
#
# Interface Endpoints (all other services):
# - Powered by AWS PrivateLink
# - Require security groups
# - Support private DNS
# - Deployed in multiple AZs for HA
#######################################

# Security Group for VPC Interface Endpoints
# Note: All ingress rules are managed via separate aws_security_group_rule resources
# to avoid conflicts between inline rules and separate rule resources
resource "aws_security_group" "vpc_endpoints" {
  name        = "${module.naming.id}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to AWS services via VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(
    local.tags,
    {
      Name = "sg-${module.naming.id}-vpc-endpoints"
    }
  )
}

# Security Group Rule: Allow HTTPS from private subnets (CIDR-based)
resource "aws_security_group_rule" "vpc_endpoints_from_vpc" {
  type              = "ingress"
  description       = "HTTPS from private subnets"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.vpc_endpoints.id
}

# Security Group Rule: Allow HTTPS from management server to VPC endpoints
resource "aws_security_group_rule" "vpc_endpoints_from_management_server" {
  count = var.enable_management_server ? 1 : 0

  type                     = "ingress"
  description              = "HTTPS from management server"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.management_server.id
  security_group_id        = aws_security_group.vpc_endpoints.id
}

#######################################
# Gateway Endpoints (Free)
#######################################

# S3 Gateway Endpoint
# Required for ECR image layer storage and S3 access from private subnets
# Gateway endpoints are free and route table based
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.public.id],
    var.enable_nat_gateway ? aws_route_table.private[*].id : [],
    aws_route_table.isolated[*].id
  )

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-s3"
    }
  )
}

#######################################
# Interface Endpoints (AWS PrivateLink)
#######################################

# KMS Interface Endpoint
# Required for encryption operations from private subnets
resource "aws_vpc_endpoint" "kms" {
  count = var.enable_kms_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-kms"
    }
  )
}

# Secrets Manager Interface Endpoint
# Required for retrieving secrets from private subnets
resource "aws_vpc_endpoint" "secrets_manager" {
  count = var.enable_secrets_manager_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-secrets-manager"
    }
  )
}

# ECR API Interface Endpoint
# Required for ECR API operations (DescribeImages, CreateRepository, etc.)
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-ecr-api"
    }
  )
}

# ECR Docker Registry Interface Endpoint
# Required for Docker push/pull operations
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-ecr-dkr"
    }
  )
}

# CloudWatch Logs Interface Endpoint
# Required for sending logs to CloudWatch from private subnets
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  count = var.enable_cloudwatch_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-cloudwatch-logs"
    }
  )
}

# CloudWatch Metrics Interface Endpoint
# Required for sending metrics to CloudWatch from private subnets
resource "aws_vpc_endpoint" "cloudwatch_metrics" {
  count = var.enable_cloudwatch_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-cloudwatch-metrics"
    }
  )
}

# Managed Prometheus Interface Endpoint
# Required for sending metrics to Managed Prometheus from private subnets
resource "aws_vpc_endpoint" "prometheus" {
  count = var.enable_prometheus_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.aps"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-prometheus"
    }
  )
}

# Bedrock Interface Endpoint
# Required for Bedrock API access from private subnets
resource "aws_vpc_endpoint" "bedrock" {
  count = var.enable_bedrock_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-bedrock"
    }
  )
}

# STS Interface Endpoint
# Required for IRSA (IAM Roles for Service Accounts) token exchange
resource "aws_vpc_endpoint" "sts" {
  count = var.enable_sts_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-sts"
    }
  )
}

# EC2 Interface Endpoint
# Required for EC2 API access from private subnets (management server)
resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_ec2_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-ec2"
    }
  )
}

#######################################
# Systems Manager (SSM) Endpoints
#######################################
# Required for Session Manager (bastion alternative)
# These endpoints enable secure access to EC2 instances without SSH keys

# SSM Interface Endpoint
# Required for Systems Manager API calls
resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_ssm_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-ssm"
    }
  )
}

# SSM Messages Interface Endpoint
# Required for Session Manager message passing
resource "aws_vpc_endpoint" "ssm_messages" {
  count = var.enable_ssm_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-ssm-messages"
    }
  )
}

# EC2 Messages Interface Endpoint
# Required for EC2 instance messaging (used by Session Manager)
resource "aws_vpc_endpoint" "ec2_messages" {
  count = var.enable_ssm_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.tags,
    {
      Name = "vpce-${module.naming.id}-ec2-messages"
    }
  )
}


