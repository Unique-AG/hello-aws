data "aws_iam_policy_document" "github_actions_terraform_state" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  statement {
    sid    = "S3StateAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
      # Read-only bucket-config attributes that aws_s3_bucket reads during
      # refresh. Without these, plan/apply fails with 403 before reaching
      # any code path that could fix this same policy. Note IAM action names
      # don't always match the S3 API call names (e.g. API GetBucketReplication
      # is IAM s3:GetReplicationConfiguration).
      "s3:GetBucketCORS",
      "s3:GetBucketLogging",
      "s3:GetBucketWebsite",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketPolicyStatus",
    ]

    # Both buckets are managed by this layer; access_logs is the destination
    # for terraform_state's access logging, so the role needs the same reads
    # on it during refresh.
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
    ]
  }

  dynamic "statement" {
    for_each = var.enable_server_side_encryption ? [1] : []
    content {
      sid    = "KMSStateEncryption"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]

      resources = [
        aws_kms_key.terraform_state[0].arn,
      ]
    }
  }
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  name = "${module.naming.iam_role_prefix}-terraform-state-access"
  role = aws_iam_role.github_actions[0].id

  policy = data.aws_iam_policy_document.github_actions_terraform_state[0].json
}

data "aws_iam_policy_document" "github_actions_deploy" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  statement {
    sid    = "AllowCoreServices"
    effect = "Allow"
    actions = [
      "ec2:*", "eks:*", "ecr:*", "elasticloadbalancing:*",
      "rds:*", "elasticache:*", "kms:*",
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
      "s3:GetBucketLocation", "s3:GetBucketPolicy", "s3:PutBucketPolicy",
      "s3:GetBucketAcl", "s3:PutBucketAcl", "s3:GetBucketVersioning",
      "s3:PutBucketVersioning", "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration", "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration", "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock", "s3:GetBucketOwnershipControls",
      "s3:PutBucketOwnershipControls", "s3:CreateBucket", "s3:DeleteBucket",
      "s3:GetBucketTagging", "s3:PutBucketTagging",
      "secretsmanager:*", "logs:*", "cloudwatch:*", "sns:*",
      "budgets:*", "acm:*", "route53:*", "ram:*",
      "cloudfront:*", "bedrock:*", "aps:*", "grafana:*",
      "codebuild:*", "events:*", "ssm:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowIAMScoped"
    effect = "Allow"
    actions = [
      "iam:*Role*", "iam:*InstanceProfile*", "iam:PassRole",
      "iam:*OpenIDConnectProvider*",
      "iam:CreateUser", "iam:DeleteUser", "iam:GetUser", "iam:ListUsers", "iam:TagUser",
      "iam:PutUserPolicy", "iam:GetUserPolicy", "iam:DeleteUserPolicy", "iam:ListUserPolicies",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:ListPolicyVersions", "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowReadOnly"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity", "organizations:DescribeOrganization"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyDangerousActions"
    effect = "Deny"
    actions = [
      "iam:CreateLoginProfile", "iam:CreateAccessKey", "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy", "iam:CreateGroup", "iam:DeleteGroup", "iam:AttachGroupPolicy",
      "organizations:*", "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count  = var.use_oidc && var.github_repository != "" ? 1 : 0
  name   = "${module.naming.iam_role_prefix}-github-actions-deploy"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_deploy[0].json
}
