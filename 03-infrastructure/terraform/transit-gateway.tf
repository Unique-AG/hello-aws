#######################################
# Transit Gateway VPC Attachment
#######################################
#
# Attaches the VPC to a Transit Gateway from the connectivity layer.
# This enables hub-and-spoke network connectivity between:
# - This VPC (landing zone)
# - Other VPCs via Transit Gateway
# - Future: On-premises networks via Direct Connect
#
# The Transit Gateway must be shared via AWS RAM from the connectivity account.
# Once shared, this attachment will be automatically accepted because the
# Transit Gateway has auto_accept_shared_attachments = "enable".
#
# Conditional: Only created when transit_gateway_id is provided.
#######################################

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  count = var.transit_gateway_id != null ? 1 : 0

  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.main.id

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = {
    Name = "${module.naming.id}-transit-gateway-attachment"
  }
}

#######################################
# Cross-Account IAM Role for Connectivity Account
#######################################
#
# Allows the connectivity account to discover and manage resources
# for Transit Gateway routing, CloudFront setup, and VPC attachments.
#
# Requires: var.connectivity_account_id
#######################################

variable "connectivity_account_principals" {
  description = "Principals in the connectivity account allowed to assume the cross-account role, as ARN suffixes. A bare role/* or user/* leaves org membership as the only real constraint."
  type        = list(string)
  default     = ["role/*-terraform-execution"]

  validation {
    condition     = !contains(var.connectivity_account_principals, "role/*") && !contains(var.connectivity_account_principals, "user/*")
    error_message = "A bare role/* or user/* defeats the condition; name the role pattern the connectivity account actually uses."
  }
}

resource "aws_iam_role" "connectivity_account" {
  count = var.enable_connectivity_account_role && var.connectivity_account_id != null ? 1 : 0

  name = "${module.naming.id}-connectivity-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.connectivity_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current[0].id
          }
          ArnLike = {
            "aws:PrincipalArn" = [
              for p in var.connectivity_account_principals :
              "arn:aws:iam::${var.connectivity_account_id}:${p}"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${module.naming.id}-connectivity-cross-account-role"
  }
}

resource "aws_iam_role_policy" "connectivity_transit_gateway" {
  #checkov:skip=CKV_AWS_290: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  count = var.enable_connectivity_account_role && var.connectivity_account_id != null ? 1 : 0

  name = "${module.naming.id}-connectivity-transit-gateway-policy"
  role = aws_iam_role.connectivity_account[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTransitGatewayVpcAttachment",
          "ec2:DescribeTransitGatewayVpcAttachments",
          "ec2:DescribeTransitGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}
