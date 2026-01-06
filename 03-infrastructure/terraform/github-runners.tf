#######################################
# GitHub Actions Self-Hosted Runners
#######################################
#
# AWS resources for GitHub Actions self-hosted runners.
# Uses CodeBuild-hosted runners with VPC connectivity.
#
# This is disabled by default - set enable_github_runners = true to enable.
#
# References:
# - https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller
# - https://aws.amazon.com/blogs/devops/using-github-actions-with-amazon-codebuild/
#######################################

#######################################
# Security Group for GitHub Runners
#######################################

resource "aws_security_group" "github_runners" {
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

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound"
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

#######################################
# Subnet for GitHub Runners
#######################################

resource "aws_subnet" "github_runners" {
  count = var.enable_github_runners ? length(local.availability_zones) : 0

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 20 + count.index) # /24 subnets starting at .20
  availability_zone = local.availability_zones[count.index]

  tags = merge(local.tags, {
    Name = "${module.naming.id}-github-runners-${local.availability_zones[count.index]}"
    Type = "github-runners"
  })
}

resource "aws_route_table_association" "github_runners" {
  count = var.enable_github_runners ? length(aws_subnet.github_runners) : 0

  subnet_id      = aws_subnet.github_runners[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#######################################
# IAM Role for GitHub Runners
#######################################

resource "aws_iam_role" "github_runners" {
  count = var.enable_github_runners ? 1 : 0

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

  tags = local.tags
}

resource "aws_iam_role_policy" "github_runners" {
  count = var.enable_github_runners ? 1 : 0

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

#######################################
# CodeBuild Project for GitHub Runners
#######################################
#
# Note: The actual GitHub Actions Runner Controller (ARC) setup
# would be deployed on EKS. This CodeBuild project is for
# workflows that need VPC access without EKS.
#
# For ARC on EKS, see: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller
#######################################

# resource "aws_codebuild_project" "github_runners" {
#   count = var.enable_github_runners ? 1 : 0
#
#   name          = "${module.naming.id}-github-runners"
#   description   = "GitHub Actions self-hosted runners with VPC access"
#   build_timeout = 60
#   service_role  = aws_iam_role.github_runners[0].arn
#
#   artifacts {
#     type = "NO_ARTIFACTS"
#   }
#
#   environment {
#     compute_type                = "BUILD_GENERAL1_SMALL"
#     image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
#     type                        = "LINUX_CONTAINER"
#     image_pull_credentials_type = "CODEBUILD"
#     privileged_mode             = true
#   }
#
#   source {
#     type            = "GITHUB"
#     location        = "https://github.com/Unique-AG/hello-aws.git"
#     git_clone_depth = 1
#     buildspec       = "buildspec.yml"
#   }
#
#   vpc_config {
#     vpc_id             = aws_vpc.main.id
#     subnets            = aws_subnet.github_runners[*].id
#     security_group_ids = [aws_security_group.github_runners[0].id]
#   }
#
#   tags = local.tags
# }
