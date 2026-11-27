#######################################
# Staff SSO: the write path for the Entra client secret
#######################################
# The identity layer holds the "[AWS] Staff SSO" Entra registration and its
# rotating client secret, and writes that secret here. Zitadel's Entra provider
# needs it; Argo CD and Grafana federate without one.
#
# In the bootstrap layer, not the cluster layer, because the identity layer
# cannot plan if this role disappears — and the cluster is rebuilt.
#
# Disabled by default: an installation that does not use Entra for staff
# sign-in creates none of this, and the blueprint keeps no Azure dependency.

variable "enable_staff_sso_secret_writer" {
  description = "Create the OIDC trust and role the identity layer uses to write the staff SSO client secret."
  type        = bool
  default     = false
}

variable "staff_sso_writer_oidc_issuer" {
  description = "Issuer of the cluster the identity layer's pipeline runs in. Must match the token's iss claim exactly, trailing slash included."
  type        = string
  default     = ""
}

variable "staff_sso_writer_subject" {
  description = "Subject permitted to assume the role, e.g. system:serviceaccount:<namespace>:<service account>."
  type        = string
  default     = ""
}

variable "staff_sso_secret_name" {
  description = "Secrets Manager name the identity layer writes."
  type        = string
  default     = "staff-sso/entra"
}

locals {
  staff_sso_enabled = var.enable_staff_sso_secret_writer && var.staff_sso_writer_oidc_issuer != "" && var.staff_sso_writer_subject != ""
  # The suffix Secrets Manager appends is not known before the secret exists,
  # so CreateSecret has to be granted against the pattern.
  staff_sso_secret_arn = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.staff_sso_secret_name}-??????"
}

data "tls_certificate" "staff_sso_writer" {
  count = local.staff_sso_enabled ? 1 : 0

  url = "${trimsuffix(var.staff_sso_writer_oidc_issuer, "/")}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "staff_sso_writer" {
  count = local.staff_sso_enabled ? 1 : 0

  url             = var.staff_sso_writer_oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.staff_sso_writer[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "staff-sso-writer-oidc"
  })
}

data "aws_iam_policy_document" "staff_sso_writer_assume" {
  count = local.staff_sso_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.staff_sso_writer[0].arn]
    }

    # Both conditions, not just the subject: without the audience any workload
    # the issuer can mint a token for could assume this role.
    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.staff_sso_writer_oidc_issuer, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.staff_sso_writer_oidc_issuer, "https://")}:sub"
      values   = [var.staff_sso_writer_subject]
    }
  }
}

resource "aws_iam_role" "staff_sso_writer" {
  count = local.staff_sso_enabled ? 1 : 0

  name               = "${module.naming.iam_role_prefix}-staff-sso-writer"
  description        = "Lets the identity layer write the staff SSO client secret, and nothing else."
  assume_role_policy = data.aws_iam_policy_document.staff_sso_writer_assume[0].json

  tags = merge(local.tags, {
    Name = "${module.naming.iam_role_prefix}-staff-sso-writer"
  })
}

data "aws_iam_policy_document" "staff_sso_writer" {
  count = local.staff_sso_enabled ? 1 : 0

  # GetSecretValue is here because Terraform reads the version back on refresh.
  statement {
    sid    = "ManageTheStaffSSOSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
    ]
    resources = [local.staff_sso_secret_arn]
  }

  # External Secrets reads this secret through a role conditioned on
  # product:Environment, so a secret created without that tag is unreadable.
  statement {
    sid       = "RequireTheEnvironmentTagOnCreate"
    effect    = "Deny"
    actions   = ["secretsmanager:CreateSecret"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestTag/product:Environment"
      values   = [var.environment]
    }
  }
}

resource "aws_iam_role_policy" "staff_sso_writer" {
  count = local.staff_sso_enabled ? 1 : 0

  name   = "staff-sso-secret"
  role   = aws_iam_role.staff_sso_writer[0].id
  policy = data.aws_iam_policy_document.staff_sso_writer[0].json
}

output "staff_sso_secret_writer_role_arn" {
  description = "Role the identity layer assumes to write the staff SSO client secret"
  value       = local.staff_sso_enabled ? aws_iam_role.staff_sso_writer[0].arn : null
}
