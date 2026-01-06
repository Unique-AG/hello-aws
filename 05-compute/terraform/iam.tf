#######################################
# IAM Roles for Service Accounts (IRSA)
#######################################
#
# IAM roles for EKS service accounts (IRSA).
# These roles can be used by Kubernetes pods to access AWS services.
#
# Note: External Secrets Operator (ESO) role is managed by platform workloads.
#######################################

#######################################
# Cross-Account IAM Role for Connectivity Account
#######################################
# Allows the connectivity account (landing zone) to create Transit Gateway
# VPC attachments for this account's EKS VPC.
#
# Connectivity account ID: 269885797075
#######################################

resource "aws_iam_role" "connectivity_account_read_only" {
  name = "${module.naming.id}-connectivity-read-only-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow connectivity account root (for development/manual runs and execution role)
        # AWS Organizations condition ensures only accounts in same org can assume
        # Condition restricts to execution role or allows any principal in connectivity account
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::269885797075:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          # Restrict to same AWS Organization (prevents confused deputy attacks)
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
          # Optional: Restrict to execution role when it exists (for production)
          # This condition allows the execution role but doesn't require it
          # For development, any principal in connectivity account can assume
          ArnLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::269885797075:role/*-terraform-execution",
              "arn:aws:iam::269885797075:user/*",
              "arn:aws:iam::269885797075:role/*"
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

# Policy to allow Transit Gateway attachment creation and VPC/Subnet/EKS discovery
resource "aws_iam_role_policy" "connectivity_transit_gateway" {
  name = "${module.naming.id}-connectivity-transit-gateway-policy"
  role = aws_iam_role.connectivity_account_read_only.id

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

locals {
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

#######################################
# EBS CSI Driver Role
#######################################
# Required for the EBS CSI driver addon to provision EBS volumes

resource "aws_iam_role" "ebs_csi" {
  name = "${module.naming.id}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ebs-csi-driver"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

#######################################
# Cluster Secrets Role
#######################################
# Used by ClusterSecretStore service account in external-secrets namespace

resource "aws_iam_role" "cluster_secrets" {
  name = "${module.naming.id}-cluster-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:external-secrets:cluster-secrets"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Name = "${module.naming.id}-cluster-secrets"
  })
}

resource "aws_iam_role_policy" "cluster_secrets" {
  name = "secrets-manager-access"
  role = aws_iam_role.cluster_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"
    }]
  })
}

#######################################
# Cert-Manager Route 53 Role
#######################################
# Used by cert-manager service account for Route 53 DNS-01 validation
# Allows cert-manager to create/delete DNS records for Let's Encrypt validation

resource "aws_iam_role" "cert_manager_route53" {
  name = "${module.naming.id}-cert-manager-route53"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Name = "${module.naming.id}-cert-manager-route53"
  })
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  name = "route53-dns01-validation"
  role = aws_iam_role.cert_manager_route53.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/*",
          "arn:aws:route53:::change/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

#######################################
# Assistants Core Role
#######################################
# Used by assistants-core service for Bedrock and S3 access

resource "aws_iam_role" "assistants_core" {
  name = "${module.naming.id}-assistants-core"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:unique:assistants-core"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Name = "${module.naming.id}-assistants-core"
  })
}

resource "aws_iam_role_policy" "assistants_core" {
  name = "bedrock-s3-secrets-access"
  role = aws_iam_role.assistants_core.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::*-ai-data"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::*-ai-data/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"
      }
    ]
  })
}

