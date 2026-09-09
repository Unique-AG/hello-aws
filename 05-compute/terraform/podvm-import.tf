#######################################
# Conduct Pod VM Image Import
#######################################
# VM Import/Export reads the disk image from S3 as a service, so it needs a
# staging bucket and a role it can assume. Both exist only while an image is
# being imported -- see the pod VM image section of 05-compute/README.md.

locals {
  podvm_import_enabled = var.enable_podvm_image_import ? 1 : 0
  podvm_import_bucket  = "s3-${module.naming.id}-podvm-import"
}

resource "aws_s3_bucket" "podvm_import" {
  #checkov:skip=CKV_AWS_18: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_144: see docs/security-baseline.md
  #checkov:skip=CKV2_AWS_62: see docs/security-baseline.md
  count = local.podvm_import_enabled

  bucket        = local.podvm_import_bucket
  force_destroy = true

  tags = merge(module.naming.tags, {
    Name    = local.podvm_import_bucket
    Purpose = "podvm-image-import"
  })
}

resource "aws_s3_bucket_versioning" "podvm_import" {
  count  = local.podvm_import_enabled
  bucket = aws_s3_bucket.podvm_import[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "podvm_import" {
  count  = local.podvm_import_enabled
  bucket = aws_s3_bucket.podvm_import[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.infrastructure.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "podvm_import" {
  count  = local.podvm_import_enabled
  bucket = aws_s3_bucket.podvm_import[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The disk image is only needed until the snapshot exists.
resource "aws_s3_bucket_lifecycle_configuration" "podvm_import" {
  count  = local.podvm_import_enabled
  bucket = aws_s3_bucket.podvm_import[0].id

  rule {
    id     = "expire-uploaded-images"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

#######################################
# The role VM Import/Export assumes
#######################################

data "aws_iam_policy_document" "podvm_import_assume" {
  statement {
    sid     = "VMImportExportAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vmie.amazonaws.com"]
    }

    # AWS requires this exact external id for VM Import/Export.
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["vmimport"]
    }

    # Without this the role is assumable on behalf of any account that names it.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "podvm_import" {
  #checkov:skip=CKV_AWS_109: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_111: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_356: see docs/security-baseline.md
  count = local.podvm_import_enabled

  statement {
    sid    = "ReadStagedImage"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.podvm_import[0].arn,
      "${aws_s3_bucket.podvm_import[0].arn}/*",
    ]
  }

  # Server-side encryption on the bucket means the service has to decrypt.
  statement {
    sid    = "DecryptStagedImage"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = [local.infrastructure.kms_key_arn]
  }

  # Snapshot and image creation cannot be resource-scoped: the resources do not
  # exist until the call that creates them.
  statement {
    sid    = "CreateSnapshotAndImage"
    effect = "Allow"
    actions = [
      "ec2:CopySnapshot",
      "ec2:Describe*",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "podvm_import" {
  count = local.podvm_import_enabled

  name               = "${module.naming.id}-podvm-import"
  description        = "Assumed by VM Import/Export to read a staged pod VM disk image"
  assume_role_policy = data.aws_iam_policy_document.podvm_import_assume.json

  tags = merge(module.naming.tags, {
    Name = "${module.naming.id}-podvm-import"
  })
}

resource "aws_iam_role_policy" "podvm_import" {
  count = local.podvm_import_enabled

  name   = "podvm-image-import"
  role   = aws_iam_role.podvm_import[0].id
  policy = data.aws_iam_policy_document.podvm_import[0].json
}
