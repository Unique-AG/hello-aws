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

  tags = merge(
    local.tags,
    {
      Name = "${module.naming.id}-transit-gateway-attachment"
    }
  )
}

#######################################
# Cross-Account IAM Role for Connectivity Account
#######################################
#
# Allows the connectivity account (landing zone) to discover resources
# for Transit Gateway routing and CloudFront setup.
#
# Requires: var.connectivity_account_id
#######################################

resource "aws_iam_role" "connectivity_account_read_only" {
  count = var.enable_connectivity_account_role && var.connectivity_account_id != null ? 1 : 0

  name = "${module.naming.id}-connectivity-read-only-role"

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
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
          ArnLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${var.connectivity_account_id}:role/*-terraform-execution",
              "arn:aws:iam::${var.connectivity_account_id}:user/*",
              "arn:aws:iam::${var.connectivity_account_id}:role/*"
            ]
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${module.naming.id}-connectivity-read-only-role"
  })
}

resource "aws_iam_role_policy" "connectivity_transit_gateway" {
  #checkov:skip=CKV_AWS_290: EC2 Describe and transit gateway actions require Resource *
  #checkov:skip=CKV_AWS_355: EC2 Describe and transit gateway actions require Resource *
  count = var.enable_connectivity_account_role && var.connectivity_account_id != null ? 1 : 0

  name = "${module.naming.id}-connectivity-transit-gateway-policy"
  role = aws_iam_role.connectivity_account_read_only[0].id

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
