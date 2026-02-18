#######################################
# EKS Pod Identity
#######################################
#
# IAM roles for EKS workloads using Pod Identity.
# These roles can be used by Kubernetes pods to access AWS services.
#
# Note: External Secrets Operator (ESO) role is managed by platform workloads.
#######################################

# Shared assume role policy for all Pod Identity roles
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

#######################################
# EBS CSI Driver Role
#######################################
# Required for the EBS CSI driver addon to provision EBS volumes

resource "aws_iam_role" "ebs_csi" {
  name               = "${module.naming.id}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ebs-csi-driver"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    sid    = "KMSForEBSEncryption"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = [local.infrastructure.kms_key_arn]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
  statement {
    sid    = "KMSEncryptDecrypt"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey",
    ]
    resources = [local.infrastructure.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ebs_csi_kms" {
  name   = "ebs-kms-encryption"
  role   = aws_iam_role.ebs_csi.id
  policy = data.aws_iam_policy_document.ebs_csi_kms.json
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
  name               = "${module.naming.id}-cluster-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-cluster-secrets"
  })
}

data "aws_iam_policy_document" "cluster_secrets" {
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"]
  }

  statement {
    sid       = "KMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [local.infrastructure.kms_key_secrets_manager_arn]
  }
}

resource "aws_iam_role_policy" "cluster_secrets" {
  name   = "secrets-manager-access"
  role   = aws_iam_role.cluster_secrets.id
  policy = data.aws_iam_policy_document.cluster_secrets.json
}

resource "aws_eks_pod_identity_association" "cluster_secrets" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.cluster_secrets.arn
}

#######################################
# Cert-Manager Route 53 Role
#######################################
# Used by cert-manager service account for Route 53 DNS-01 validation
# Allows cert-manager to create/delete DNS records for Let's Encrypt validation

resource "aws_iam_role" "cert_manager_route53" {
  name               = "${module.naming.id}-cert-manager-route53"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-cert-manager-route53"
  })
}

data "aws_iam_policy_document" "cert_manager_route53" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  statement {
    effect = "Allow"
    actions = [
      "route53:GetChange",
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      "arn:aws:route53:::hostedzone/*",
      "arn:aws:route53:::change/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  name   = "route53-dns01-validation"
  role   = aws_iam_role.cert_manager_route53.id
  policy = data.aws_iam_policy_document.cert_manager_route53.json
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
  name               = "${module.naming.id}-assistants-core"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-assistants-core"
  })
}

data "aws_iam_policy_document" "assistants_core" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*::inference-profile/eu.*",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::*-ai-data"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::*-ai-data/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"]
  }
}

resource "aws_iam_role_policy" "assistants_core" {
  name   = "bedrock-s3-secrets-access"
  role   = aws_iam_role.assistants_core.id
  policy = data.aws_iam_policy_document.assistants_core.json
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
  name               = "${module.naming.id}-litellm"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-litellm"
  })
}

data "aws_iam_policy_document" "litellm" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*::inference-profile/eu.*",
      "arn:aws:bedrock:*::inference-profile/global.*",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:application-inference-profile/*",
    ]
  }
}

resource "aws_iam_role_policy" "litellm" {
  name   = "bedrock-access"
  role   = aws_iam_role.litellm.id
  policy = data.aws_iam_policy_document.litellm.json
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
  name               = "${module.naming.id}-ingestion"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingestion"
  })
}

data "aws_iam_policy_document" "ingestion" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::*-ai-data"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::*-ai-data/*"]
  }
}

resource "aws_iam_role_policy" "ingestion" {
  name   = "s3-access"
  role   = aws_iam_role.ingestion.id
  policy = data.aws_iam_policy_document.ingestion.json
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
  name               = "${module.naming.id}-ingestion-worker"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingestion-worker"
  })
}

data "aws_iam_policy_document" "ingestion_worker" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*::inference-profile/eu.*",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::*-ai-data"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::*-ai-data/*"]
  }
}

resource "aws_iam_role_policy" "ingestion_worker" {
  name   = "bedrock-s3-access"
  role   = aws_iam_role.ingestion_worker.id
  policy = data.aws_iam_policy_document.ingestion_worker.json
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
  name               = "${module.naming.id}-speech"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-speech"
  })
}

data "aws_iam_policy_document" "speech" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_290: see docs/security-baseline.md
  statement {
    effect = "Allow"
    actions = [
      "transcribe:StartStreamTranscription",
      "transcribe:StartStreamTranscriptionWebSocket",
      "transcribe:StartTranscriptionJob",
      "transcribe:GetTranscriptionJob",
      "transcribe:ListTranscriptionJobs",
      "transcribe:DeleteTranscriptionJob",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "speech" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_290: see docs/security-baseline.md
  name   = "transcribe-access"
  role   = aws_iam_role.speech.id
  policy = data.aws_iam_policy_document.speech.json
}

resource "aws_eks_pod_identity_association" "speech" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "backend-service-speech"
  role_arn        = aws_iam_role.speech.arn
}

#######################################
# AWS Load Balancer Controller Role
#######################################
# Used by AWS Load Balancer Controller for managing ALBs/NLBs
# and registering pod IPs into target groups via TargetGroupBinding

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${module.naming.id}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(local.tags, {
    Name = "${module.naming.id}-aws-lb-controller"
  })
}

data "aws_iam_policy_document" "aws_lb_controller" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_290: see docs/security-baseline.md
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:DescribeCoipPools",
      "ec2:GetCoipPoolUsage",
      "ec2:GetSecurityGroupsForVpc",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeleteLoadBalancer",
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["cognito-idp:DescribeUserPoolClient"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "acm:GetCertificate",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "aws_lb_controller" {
  #checkov:skip=CKV_AWS_355: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_290: see docs/security-baseline.md
  name   = "aws-lb-controller"
  role   = aws_iam_role.aws_lb_controller.id
  policy = data.aws_iam_policy_document.aws_lb_controller.json
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "unique"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lb_controller.arn
}
