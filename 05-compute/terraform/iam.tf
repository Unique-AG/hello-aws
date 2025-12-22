#######################################
# IAM Roles for Service Accounts (IRSA)
#######################################
#
# IAM roles for EKS service accounts (IRSA).
# These roles can be used by Kubernetes pods to access AWS services.
#
# Note: External Secrets Operator (ESO) role is managed by platform workloads.
#######################################

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

