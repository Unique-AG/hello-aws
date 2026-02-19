# Security Group for VPC Interface Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${module.naming.id}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "sg-${module.naming.id}-vpc-endpoints"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpc_endpoints_to_vpc" {
  for_each = toset(var.secondary_cidr_enabled ? [var.vpc_cidr, local.secondary_cidr] : [var.vpc_cidr])

  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS to AWS services via VPC endpoints"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_vpc" {
  for_each = toset(var.secondary_cidr_enabled ? [var.vpc_cidr, local.secondary_cidr] : [var.vpc_cidr])

  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from VPC (${each.value})"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_management_server" {
  count = var.management_server_enabled ? 1 : 0

  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS from management server"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.management_server.id
}

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
    aws_route_table.private[*].id,
    aws_route_table.isolated[*].id
  )

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTerraformState"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${local.terraform_state_bucket}",
          "arn:aws:s3:::${local.terraform_state_bucket}/*"
        ]
      },
      {
        Sid       = "AllowApplicationData"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::s3-${module.naming.id}-application-data",
          "arn:aws:s3:::s3-${module.naming.id}-application-data/*",
          "arn:aws:s3:::s3-${module.naming.id}-ai-data",
          "arn:aws:s3:::s3-${module.naming.id}-ai-data/*"
        ]
      },
      {
        Sid       = "AllowECRLayers"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::prod-${var.aws_region}-starport-layer-bucket",
          "arn:aws:s3:::prod-${var.aws_region}-starport-layer-bucket/*"
        ]
      }
    ]
  })

  tags = {
    Name = "vpce-${module.naming.id}-s3"
  }
}

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

  tags = {
    Name = "vpce-${module.naming.id}-kms"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-secrets-manager"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-ecr-api"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-ecr-dkr"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-cloudwatch-logs"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-cloudwatch-metrics"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-prometheus"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-bedrock"
  }
}

# Bedrock Runtime Interface Endpoint
# Required for Bedrock model invocations from private subnets
resource "aws_vpc_endpoint" "bedrock_runtime" {
  count = var.enable_bedrock_endpoint ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-bedrock-runtime"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-sts"
  }
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

  tags = {
    Name = "vpce-${module.naming.id}-ec2"
  }
}

# SSM Interface Endpoint
# Required for Systems Manager API calls
resource "aws_vpc_endpoint" "ssm" {
  count = var.ssm_endpoints_enabled ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-ssm"
  }
}

# SSM Messages Interface Endpoint
# Required for Session Manager message passing
resource "aws_vpc_endpoint" "ssm_messages" {
  count = var.ssm_endpoints_enabled ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-ssm-messages"
  }
}

# EC2 Messages Interface Endpoint
# Required for EC2 instance messaging (used by Session Manager)
resource "aws_vpc_endpoint" "ec2_messages" {
  count = var.ssm_endpoints_enabled ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-${module.naming.id}-ec2-messages"
  }
}


