resource "aws_security_group" "github_runners" {
  #trivy:ignore:AVD-AWS-0104 Runners require HTTPS egress to GitHub API and package registries
  count = var.enable_github_runners ? 1 : 0

  name        = "${module.naming.id}-github-runners"
  description = "Security group for GitHub Actions self-hosted runners"
  vpc_id      = aws_vpc.main.id

  # Outbound to internet (for GitHub API, package registries)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for GitHub API and registries"
  }

  # Outbound to VPC endpoints
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS to VPC endpoints"
  }

  tags = merge(local.tags, {
    Name = "${module.naming.id}-github-runners-sg"
  })
}

resource "aws_subnet" "github_runners" {
  count = var.github_runners_enabled ? length(local.availability_zones) : 0

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_allocations.runners.newbits, local.subnet_allocations.runners.start + count.index) # /26 subnets, non-overlapping
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name = "${module.naming.id}-github-runners-${local.availability_zones[count.index]}"
    Type = "github-runners"
  }
}

resource "aws_route_table_association" "github_runners" {
  count = var.github_runners_enabled && var.enable_nat_gateway ? length(aws_subnet.github_runners) : 0

  subnet_id      = aws_subnet.github_runners[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_iam_role" "github_runners" {
  count = var.github_runners_enabled ? 1 : 0

  name = "${module.naming.id}-github-runners"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_runners" {
  count = var.github_runners_enabled ? 1 : 0

  name = "github-runners-policy"
  role = aws_iam_role.github_runners[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        Condition = {
          StringEquals = {
            "ec2:Subnet" = [for subnet in aws_subnet.github_runners : subnet.arn]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:github-*"
      }
    ]
  })
}

