#######################################
# EKS Fargate — sandbox isolation (README: "Fargate Sandbox Isolation")
# Gated on var.fargate_profiles — an empty map creates nothing.
#######################################

locals {
  fargate_enabled = length(var.fargate_profiles) > 0
  fargate_count   = local.fargate_enabled ? 1 : 0
}

# Pod execution role. The principal is eks-fargate-pods.amazonaws.com, not the Pod
# Identity one. The managed policy grants ECR pull only.
data "aws_iam_policy_document" "fargate_pod_execution_assume" {
  count = local.fargate_count

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
    # Confused-deputy guard: only this cluster's profiles may assume it.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${aws_eks_cluster.main.name}/*"]
    }
  }
}

resource "aws_iam_role" "fargate_pod_execution" {
  count              = local.fargate_count
  name               = "${module.naming.id}-fargate-pod-execution"
  assume_role_policy = data.aws_iam_policy_document.fargate_pod_execution_assume[0].json
  tags               = merge(module.naming.tags, { Name = "role-${module.naming.id}-fargate-pod-execution" })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  count      = local.fargate_count
  role       = aws_iam_role.fargate_pod_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# The managed policy is ECR-pull-only, so the Fargate log router needs these added
# or the sandbox audit log fails with AccessDenied and nothing says so.
data "aws_iam_policy_document" "fargate_logging" {
  count = local.fargate_count

  statement {
    sid    = "FargateLogRouter"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }
}

resource "aws_iam_role_policy" "fargate_logging" {
  count  = local.fargate_count
  name   = "fargate-cloudwatch-logging"
  role   = aws_iam_role.fargate_pod_execution[0].id
  policy = data.aws_iam_policy_document.fargate_logging[0].json
}

# Selectors are immutable — changing one forces destroy and recreate. The sandbox
# profile must match only the runtime pods, not sbx-gateway, which shares the
# namespace but has to stay on EC2.
resource "aws_eks_fargate_profile" "this" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "${module.naming.id}-${each.key}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution[0].arn
  subnet_ids             = local.infrastructure.private_subnet_ids

  selector {
    namespace = each.value.namespace
    labels    = each.value.labels
  }

  tags = merge(module.naming.tags, { Name = "${module.naming.id}-${each.key}" })

  # EKS checks the role's permissions when it creates the profile.
  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution,
    aws_iam_role_policy.fargate_logging,
  ]
}

# The L4 floor for sandbox pods: gateway, DNS, in-VPC pull, S3 layers; router in.
# Inert until layer 06 attaches it with a SecurityGroupPolicy.
resource "aws_security_group" "fargate_sandbox" {
  #checkov:skip=CKV2_AWS_5:Attached to pods by a Kubernetes SecurityGroupPolicy in layer 06, which checkov cannot see.
  count       = local.fargate_count
  name        = "${module.naming.id}-fargate-sandbox"
  description = "Sandbox pods on Fargate - egress to sbx-gateway, DNS, in-VPC and S3 pull only"
  vpc_id      = local.infrastructure.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(module.naming.tags, { Name = "sg-${module.naming.id}-fargate-sandbox" })
}

resource "aws_vpc_security_group_egress_rule" "fargate_sandbox_gateway" {
  count             = local.fargate_count
  security_group_id = aws_security_group.fargate_sandbox[0].id
  description       = "Sandbox HTTP(S) egress funneled through the sbx-gateway proxy"
  from_port         = 3128
  to_port           = 3128
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "fargate_sandbox_dns_udp" {
  count             = local.fargate_count
  security_group_id = aws_security_group.fargate_sandbox[0].id
  description       = "DNS (UDP) to in-cluster CoreDNS"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "fargate_sandbox_dns_tcp" {
  count             = local.fargate_count
  security_group_id = aws_security_group.fargate_sandbox[0].id
  description       = "DNS (TCP) to in-cluster CoreDNS"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "fargate_sandbox_https_invpc" {
  count             = local.fargate_count
  security_group_id = aws_security_group.fargate_sandbox[0].id
  description       = "In-VPC HTTPS for image pull (ECR interface endpoints) and the EKS API"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# ECR image layers come from S3 via the gateway endpoint, reached by prefix list
# rather than an in-VPC address, so the rule above does not cover them.
resource "aws_vpc_security_group_egress_rule" "fargate_sandbox_s3" {
  count             = local.fargate_count
  security_group_id = aws_security_group.fargate_sandbox[0].id
  description       = "HTTPS to the S3 gateway endpoint (ECR image layers)"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id
}

resource "aws_vpc_security_group_ingress_rule" "fargate_sandbox_runtime" {
  count             = local.fargate_count
  security_group_id = aws_security_group.fargate_sandbox[0].id
  description       = "Sandbox runtime port from the in-cluster sandbox-router"
  from_port         = 8888
  to_port           = 8888
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Under strict pod-SG mode the pod carries only this SG, so the control plane
# cannot reach its kubelet and logs/exec time out without this.
resource "aws_vpc_security_group_ingress_rule" "fargate_sandbox_kubelet" {
  count                        = local.fargate_count
  security_group_id            = aws_security_group.fargate_sandbox[0].id
  description                  = "Allow the EKS control plane to reach the sandbox pod kubelet for logs/exec"
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

# Reciprocal: the API server's SG must admit the sandbox SG, for the same reason.
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_fargate_sandbox" {
  count                        = local.fargate_count
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow HTTPS from Fargate sandbox pods to the EKS API server"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.fargate_sandbox[0].id
}

# Consumed by the layer-06 SecurityGroupPolicy that pins sandbox pods to this SG.
output "fargate_sandbox_security_group_id" {
  description = "Security group ID for sandbox pods on Fargate (referenced by the layer-06 SecurityGroupPolicy)"
  value       = local.fargate_enabled ? aws_security_group.fargate_sandbox[0].id : null
}
