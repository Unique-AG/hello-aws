#######################################
# Karpenter — the parts that need no cluster API
#######################################
# Self-managed Karpenter rather than EKS Auto Mode: Auto Mode cannot enable
# compute without also taking over load balancing and block storage, and its
# built-in node pools are AMD-only, which AWS-CST-01's Graviton pools rule out.
#
# The NodePool and EC2NodeClass objects are Kubernetes custom resources and are
# not here; this file is only what the AWS API owns.

locals {
  karpenter_node_role_name = "${module.naming.id}-karpenter-node"
}

#######################################
# Node role — the identity Karpenter's instances run as
#######################################
# Separate from the managed node groups' role: those keep the Kata sandbox
# hosts, and a shared role would make one blast radius out of two.

resource "aws_iam_role" "karpenter_node" {
  name = local.karpenter_node_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(module.naming.tags, {
    Name = local.karpenter_node_role_name
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Deliberately no AmazonEKS_CNI_Policy: #241 moved it off the node role onto a
# Pod Identity association for aws-node, and this role follows that.

resource "aws_iam_role_policy" "karpenter_node_ecr_pull_through_cache" {
  name = "ecr-pull-through-cache"
  role = aws_iam_role.karpenter_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

# A managed node group gets an access entry created for it; a Karpenter node is
# a plain EC2 instance and gets none, so in API authentication mode it would
# never join.
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

#######################################
# Interruption queue
#######################################
# Karpenter drains a node on a Spot interruption, a rebalance recommendation or
# a scheduled change instead of losing it; without the queue it learns when the
# instance is already gone.

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${module.naming.id}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(module.naming.tags, {
    Name = "${module.naming.id}-karpenter-interruption"
  })
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }

    # Without this any account's EventBridge could write to the queue.
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for r in aws_cloudwatch_event_rule.karpenter : r.arn]
    }
  }

  statement {
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.url
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

locals {
  # The four events Karpenter acts on. Spot interruption gives two minutes;
  # rebalance arrives earlier and is advisory; the other two cover retirement
  # and a stop or terminate from outside Karpenter.
  karpenter_events = {
    spot_interruption = {
      source      = "aws.ec2"
      detail_type = "EC2 Spot Instance Interruption Warning"
    }
    rebalance = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance Rebalance Recommendation"
    }
    scheduled_change = {
      source      = "aws.health"
      detail_type = "AWS Health Event"
    }
    state_change = {
      source      = "aws.ec2"
      detail_type = "EC2 Instance State-change Notification"
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.karpenter_events

  name        = "${module.naming.id}-karpenter-${replace(each.key, "_", "-")}"
  description = "Karpenter interruption handling: ${each.value.detail_type}"

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })

  tags = module.naming.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_events

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

#######################################
# Controller role
#######################################

resource "aws_iam_role" "karpenter_controller" {
  name               = "${module.naming.id}-karpenter"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = merge(module.naming.tags, {
    Name = "${module.naming.id}-karpenter"
  })
}

data "aws_iam_policy_document" "karpenter_controller" {
  # Reading what it may launch. These are describe-only and take no resource
  # condition, because Karpenter chooses from the whole catalogue.
  statement {
    sid    = "ReadEC2"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }

  # Pricing and the AMI parameters Karpenter resolves node images from.
  statement {
    sid       = "ReadPricingAndAMIParameters"
    effect    = "Allow"
    actions   = ["pricing:GetProducts", "ssm:GetParameter"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }

  # Launching. RunInstances and CreateFleet are scoped by the discovery tag on
  # the subnets and security groups, so Karpenter cannot launch into a network
  # this layer has not marked for it.
  statement {
    sid    = "LaunchInstances"
    effect = "Allow"
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:RunInstances",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
  }

  # The AMI, subnet, security group and instance profile a launch references
  # are not tagged by the request, so they need their own statement.
  statement {
    sid    = "LaunchInstancesSupportingResources"
    effect = "Allow"
    actions = [
      "ec2:CreateFleet",
      "ec2:RunInstances",
      "ec2:CreateLaunchTemplate",
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}::image/*",
      "arn:aws:ec2:${var.aws_region}::snapshot/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:launch-template/*",
    ]
  }

  statement {
    sid       = "TagOnCreate"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
  }

  # Terminating and retagging only what it owns.
  statement {
    sid    = "ManageOwnedInstances"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
      "ec2:CreateTags",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
  }

  # Karpenter builds the instance profile for the node role itself.
  statement {
    sid    = "ManageInstanceProfile"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
  }

  # Only the node role may be handed to an instance.
  statement {
    sid       = "PassNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid    = "InterruptionQueue"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "karpenter"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = var.karpenter_namespace
  service_account = var.karpenter_service_account
  role_arn        = aws_iam_role.karpenter_controller.arn
}
