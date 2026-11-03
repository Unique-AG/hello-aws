#######################################
# Conduct Pod VM — launch template
#######################################
# A peer-pod sandbox is its own EC2 instance, outside the cluster's IAM, so the
# node role does not reach it. Without an instance profile it cannot authenticate
# to ECR and the container fails with CreateContainerRequest timed out.
#
# cloud-api-adaptor has no instance-profile field; a launch template is the only
# supported way to give the VM credentials (USE_PODVM_LAUNCHTEMPLATE).

locals {
  podvm_enabled = var.podvm_ami_id != ""
  podvm_count   = local.podvm_enabled ? 1 : 0
}

data "aws_iam_policy_document" "podvm_assume" {
  count = local.podvm_count

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "podvm" {
  count              = local.podvm_count
  name               = "${module.naming.id}-podvm"
  assume_role_policy = data.aws_iam_policy_document.podvm_assume[0].json
  tags               = merge(module.naming.tags, { Name = "role-${module.naming.id}-podvm" })
}

# Pull only, plus the pull-through import the node role also carries: the sandbox
# image is mirrored, so a cold cache needs the import on first use.
data "aws_iam_policy_document" "podvm_ecr" {
  count = local.podvm_count

  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchImportUpstreamImage",
      "ecr:CreateRepository",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }
}

resource "aws_iam_role_policy" "podvm_ecr" {
  count  = local.podvm_count
  name   = "ecr-pull"
  role   = aws_iam_role.podvm[0].id
  policy = data.aws_iam_policy_document.podvm_ecr[0].json
}

resource "aws_iam_instance_profile" "podvm" {
  count = local.podvm_count
  name  = "${module.naming.id}-podvm"
  role  = aws_iam_role.podvm[0].name
  tags  = merge(module.naming.tags, { Name = "${module.naming.id}-podvm" })
}

# The adaptor launches from this template, so the AMI, instance type, security
# group and instance profile all come from here rather than peer-pods values.
resource "aws_launch_template" "podvm" {
  #checkov:skip=CKV_AWS_341: see docs/security-baseline.md
  count = local.podvm_count

  name          = "${module.naming.id}-podvm"
  image_id      = var.podvm_ami_id
  instance_type = var.podvm_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.podvm[0].arn
  }

  vpc_security_group_ids = [aws_security_group.peer_pods.id]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.podvm_root_volume_size
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = local.infrastructure.kms_key_arn
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # The tag the peer-pods IAM policy conditions on for launch and termination.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(module.naming.tags, { Name = "${module.naming.id}-podvm", PeerPod = "true" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(module.naming.tags, { Name = "${module.naming.id}-podvm", PeerPod = "true" })
  }

  tags = merge(module.naming.tags, { Name = "${module.naming.id}-podvm" })
}
