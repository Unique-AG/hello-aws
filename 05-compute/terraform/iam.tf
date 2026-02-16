#######################################
# EKS Pod Identity
#######################################
#
# IAM roles for EKS workloads using Pod Identity.
# These roles can be used by Kubernetes pods to access AWS services.
#
# Note: External Secrets Operator (ESO) role is managed by platform workloads.
#######################################

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
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-ebs-csi-driver"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

#######################################
# Cluster Secrets Role
#######################################
# Used by ClusterSecretStore service account in unique namespace

resource "aws_iam_role" "cluster_secrets" {
  name = "${module.naming.id}-cluster-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-cluster-secrets"
  }
}

resource "aws_iam_role_policy" "cluster_secrets" {
  name = "secrets-manager-access"
  role = aws_iam_role.cluster_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = local.infrastructure.kms_key_secrets_manager_arn
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "cluster_secrets" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.cluster_secrets.arn
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
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-cert-manager-route53"
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
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
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "cert-manager"
  role_arn        = aws_iam_role.cert_manager_route53.arn
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
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-assistants-core"
  }
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
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*::inference-profile/eu.*",
          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
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

resource "aws_eks_pod_identity_association" "assistants_core" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "assistants-core"
  role_arn        = aws_iam_role.assistants_core.arn
}

#######################################
# LiteLLM Role
#######################################
# Used by LiteLLM proxy for Bedrock model invocation

resource "aws_iam_role" "litellm" {
  name = "${module.naming.id}-litellm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-litellm"
  }
}

resource "aws_iam_role_policy" "litellm" {
  name = "bedrock-access"
  role = aws_iam_role.litellm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*::inference-profile/eu.*",
          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "litellm" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "litellm"
  role_arn        = aws_iam_role.litellm.arn
}

#######################################
# Ingestion Role
#######################################
# Used by ingestion service for S3 access

resource "aws_iam_role" "ingestion" {
  name = "${module.naming.id}-ingestion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-ingestion"
  }
}

resource "aws_iam_role_policy" "ingestion" {
  name = "s3-access"
  role = aws_iam_role.ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "ingestion" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "backend-service-ingestion"
  role_arn        = aws_iam_role.ingestion.arn
}

#######################################
# Ingestion Worker Role
#######################################
# Used by ingestion-worker service for Bedrock and S3 access

resource "aws_iam_role" "ingestion_worker" {
  name = "${module.naming.id}-ingestion-worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-ingestion-worker"
  }
}

resource "aws_iam_role_policy" "ingestion_worker" {
  name = "bedrock-s3-access"
  role = aws_iam_role.ingestion_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*::inference-profile/eu.*",
          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
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
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "ingestion_worker" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "backend-service-ingestion-worker"
  role_arn        = aws_iam_role.ingestion_worker.arn
}

#######################################
# Speech Role
#######################################
# Used by speech service for AWS Transcribe access

resource "aws_iam_role" "speech" {
  name = "${module.naming.id}-speech"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = {
    Name = "${module.naming.id}-speech"
  }
}

resource "aws_iam_role_policy" "speech" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_290: see docs/security-baseline.md
  name = "transcribe-access"
  role = aws_iam_role.speech.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "transcribe:StartStreamTranscription",
          "transcribe:StartStreamTranscriptionWebSocket",
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob",
          "transcribe:ListTranscriptionJobs",
          "transcribe:DeleteTranscriptionJob"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "speech" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "backend-service-speech"
  role_arn        = aws_iam_role.speech.arn
}
