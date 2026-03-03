#######################################
# EKS Cluster
#######################################
#
# Amazon Elastic Kubernetes Service (EKS) cluster configuration.
# Provides managed Kubernetes for containerized workloads.
#######################################

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "${module.naming.id}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach AWS managed policies to EKS cluster role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "eks-${module.naming.id}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = local.infrastructure.private_subnet_ids
    endpoint_private_access = var.eks_endpoint_private_access
    endpoint_public_access  = var.eks_endpoint_public_access
    # Only set public_access_cidrs if public access is enabled
    # AWS requires this to be empty list when public access is disabled
    public_access_cidrs = var.eks_endpoint_public_access ? var.eks_endpoint_public_access_cidrs : []
    security_group_ids  = [aws_security_group.eks_cluster.id]
  }

  # Encryption configuration
  encryption_config {
    provider {
      key_arn = local.infrastructure.kms_key_arn
    }
    resources = ["secrets"]
  }

  # Enable control plane logging
  enabled_cluster_log_types = var.eks_enabled_cluster_log_types

  # Authentication mode: API only (access entries)
  # ConfigMap authentication is disabled for enhanced security
  # All access is managed via EKS access entries (modern approach)
  access_config {
    authentication_mode = "API"
  }

  # CloudWatch log group for EKS cluster logs
  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# EKS Access Entry for Management Server
# Allows the management server IAM role to authenticate to the EKS cluster
resource "aws_eks_access_entry" "management_server" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = data.terraform_remote_state.infrastructure.outputs.ssm_instance_role_arn
  kubernetes_groups = []
  type              = "STANDARD"

  tags = {
    Name = "${module.naming.id}-management-server-access"
  }
}

# EKS Access Policy for Management Server
# Grants cluster admin access to the management server
resource "aws_eks_access_policy_association" "management_server" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.terraform_remote_state.infrastructure.outputs.ssm_instance_role_arn
  access_scope {
    type       = "cluster"
    namespaces = []
  }
}

# EKS Access Entry for Sandbox Administrator
# Allows the SandboxAdministrator role to authenticate to the EKS cluster
resource "aws_eks_access_entry" "sandbox_admin" {
  count = var.environment == "sbx" ? 1 : 0

  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/SandboxAdministrator"
  kubernetes_groups = []
  type              = "STANDARD"

  tags = {
    Name = "${module.naming.id}-sandbox-admin-access"
  }
}

# EKS Access Policy for Sandbox Administrator
# Grants cluster admin access to sandbox administrators
resource "aws_eks_access_policy_association" "sandbox_admin" {
  count = var.environment == "sbx" ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/SandboxAdministrator"
  access_scope {
    type       = "cluster"
    namespaces = []
  }

  depends_on = [aws_eks_access_entry.sandbox_admin]
}

# CloudWatch Log Group for EKS Cluster
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/eks-${module.naming.id}/cluster"
  retention_in_days = max(var.eks_cluster_log_retention_days, 365)
  kms_key_id        = local.infrastructure.kms_key_arn

  tags = {
    Name = "${module.naming.id}-eks-cluster-logs"
  }
}

# Security Group for EKS Cluster (control plane ENIs + managed node communication)
resource "aws_security_group" "eks_cluster" {
  name        = "${module.naming.id}-eks-cluster"
  description = "Security group for EKS cluster (control plane and node communication)"
  vpc_id      = local.infrastructure.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${module.naming.id}-eks-cluster-sg"
  }
}

# Security Group Rule: Allow inbound from EKS nodes to cluster
resource "aws_security_group_rule" "eks_cluster_from_nodes" {
  type                     = "ingress"
  description              = "Allow inbound from EKS nodes"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_vpc_endpoints" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow HTTPS from VPC endpoints (kubectl from within VPC)"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = local.infrastructure.vpc_endpoints_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_vpc" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow HTTPS outbound to VPC"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow outbound to nodes for kubelet and webhooks"
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# Allow inbound from management server to cluster (if management server exists)
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_management_server" {
  count = try(data.terraform_remote_state.infrastructure.outputs.management_server_security_group_id, null) != null ? 1 : 0

  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow HTTPS from management server for kubectl access"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = data.terraform_remote_state.infrastructure.outputs.management_server_security_group_id
}

# Security Group for EKS Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "${module.naming.id}-eks-nodes"
  description = "Security group for EKS worker nodes"
  vpc_id      = local.infrastructure.vpc_id

  tags = {
    Name = "${module.naming.id}-eks-nodes-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_self" {
  #checkov:skip=CKV_AWS_24: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_25: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_260: see docs/security-baseline.md
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow node-to-node communication"
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_vpc" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow inbound from VPC CIDR"
  from_port         = 0
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Node egress — primary VPC CIDR (all TCP for pod/service/DNS/kubelet traffic)
resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_vpc" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow all TCP outbound to VPC primary CIDR"
  from_port         = 0
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Node egress — secondary CIDR for pod networking (VPC CNI assigns pod IPs here)
resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_secondary_cidr" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow all TCP outbound to VPC secondary CIDR (pod networking)"
  from_port         = 0
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = local.secondary_cidr
}

# Node egress — HTTPS to EKS control plane (via SG reference, covers private endpoint)
resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_cluster" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow HTTPS outbound to EKS cluster control plane"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

# Node egress — IMDS (instance metadata service for IAM credentials)
resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_imds" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow outbound to EC2 instance metadata service"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "169.254.169.254/32"
}

# Node ingress — DNS (UDP) from VPC (cross-node CoreDNS traffic)
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_dns_udp" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow DNS (UDP) inbound from VPC"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Node egress — DNS (UDP) to VPC DNS resolver
resource "aws_vpc_security_group_egress_rule" "eks_nodes_dns_udp" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow DNS (UDP) outbound to VPC"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Node egress — S3 via gateway endpoint (ECR image layers are stored in S3)
resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_s3" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow HTTPS outbound to S3 (ECR image layers)"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id
}

data "aws_ec2_managed_prefix_list" "s3" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.${var.aws_region}.s3"]
  }
}

# Security Group Rule: Allow inbound from Ingress NLB to EKS managed cluster SG
# NLB health checks target pod IPs directly; the EKS managed cluster SG
# (applied to all nodes) must allow this traffic for health checks to pass.
resource "aws_security_group_rule" "eks_cluster_sg_from_nlb" {
  count = local.infrastructure.ingress_nlb_security_group_id != null ? 1 : 0

  type                     = "ingress"
  description              = "Allow inbound from Ingress NLB for health checks"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = local.infrastructure.ingress_nlb_security_group_id
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# Security Group Rule: Allow inbound from EKS cluster to nodes
resource "aws_security_group_rule" "eks_nodes_from_cluster" {
  type                     = "ingress"
  description              = "Allow inbound from EKS cluster"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_group" {
  name = "${module.naming.id}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach AWS managed policies to node group role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# ECR Pull-Through Cache policy - allows nodes to import images from upstream registries
resource "aws_iam_role_policy" "eks_node_ecr_pull_through_cache" {
  name = "ecr-pull-through-cache"
  role = aws_iam_role.eks_node_group.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

#######################################
# EKS Addons
#######################################

# EKS Pod Identity Agent Addon - Required for Pod Identity associations
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.pool]
}

# EBS CSI Driver Addon - Required for PersistentVolumeClaims with gp3 storage
# Pod Identity association is managed via standalone aws_eks_pod_identity_association.ebs_csi
# service_account_role_arn is ignored because cross-account assumed roles cannot
# call UpdateAddon with role changes (PassRole restriction)
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.eks_ebs_csi_driver_version
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.pool]

  lifecycle {
    ignore_changes = [service_account_role_arn]
  }

  tags = {
    Name = "${module.naming.id}-ebs-csi-addon"
  }
}

# CoreDNS Addon
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.pool]
}

# kube-proxy Addon
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.pool]
}

# VPC CNI Addon
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.pool]
}

#######################################
# EKS Node Groups
#######################################

# Launch template to attach the eks_nodes security group to managed node groups.
# EKS managed node groups don't expose a security_group_ids attribute directly;
# a launch template is the only way to add additional SGs beyond the auto-created
# cluster security group.
resource "aws_launch_template" "eks_nodes" {
  #checkov:skip=CKV_AWS_341: see docs/security-baseline.md
  for_each = var.eks_node_groups

  name = "${module.naming.id}-${each.key}"

  vpc_security_group_ids = [
    aws_security_group.eks_nodes.id,
  ]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = each.value.disk_size
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = local.infrastructure.kms_key_arn
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${module.naming.id}-${each.key}"
  }
}

resource "aws_eks_node_group" "pool" {
  for_each = var.eks_node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${module.naming.id}-${each.key}"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = local.infrastructure.private_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type

  launch_template {
    id      = aws_launch_template.eks_nodes[each.key].id
    version = aws_launch_template.eks_nodes[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = each.value.max_unavailable
  }

  labels = {
    lifecycle   = each.value.labels.lifecycle
    scalability = each.value.labels.scalability
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]

  tags = {
    Name = "${module.naming.id}-${each.key}"
  }
}

