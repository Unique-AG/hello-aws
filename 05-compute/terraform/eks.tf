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
  #checkov:skip=CKV_AWS_338: see docs/security-baseline.md
  name              = "/aws/eks/eks-${module.naming.id}/cluster"
  retention_in_days = var.eks_cluster_log_retention_days
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

# Allow inbound from management server to cluster (if management server exists)
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_management_server" {
  count = try(data.terraform_remote_state.infrastructure.outputs.management_server_security_group_id, null) != null ? 1 : 0

<<<<<<< HEAD
  type                     = "ingress"
  description              = "Allow inbound from management server for kubectl access"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = data.terraform_remote_state.infrastructure.outputs.management_server_security_group_id
  security_group_id        = aws_security_group.eks_cluster.id
=======
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Allow HTTPS from management server for kubectl access"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = data.terraform_remote_state.infrastructure.outputs.management_server_security_group_id
>>>>>>> cb78cec (fix: migrate all SG rules to aws_vpc_security_group_*_rule resources)
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
  depends_on                  = [aws_eks_node_group.main]
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

  depends_on = [aws_eks_node_group.main]

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

  depends_on = [aws_eks_node_group.main]
}

# kube-proxy Addon
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

# VPC CNI Addon
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

#######################################
# EKS Node Group
#######################################

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${module.naming.id}-node-group"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = local.infrastructure.private_subnet_ids

  instance_types = var.eks_node_group_instance_types
  capacity_type  = var.eks_node_group_capacity_type
  disk_size      = var.eks_node_group_disk_size

  scaling_config {
    desired_size = var.eks_node_group_desired_size
    min_size     = var.eks_node_group_min_size
    max_size     = var.eks_node_group_max_size
  }

  update_config {
    max_unavailable = var.eks_node_group_update_config.max_unavailable
  }

  labels = var.eks_node_group_labels

  dynamic "taint" {
    for_each = var.eks_node_group_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  # Ensure cluster is ready before creating node group
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]

  tags = {
    Name = "${module.naming.id}-node-group"
  }
}

# Large node group for system applications (Kong, etc.)
resource "aws_eks_node_group" "large" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${module.naming.id}-node-group-large"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = local.infrastructure.private_subnet_ids

  instance_types = var.eks_node_group_instance_types
  capacity_type  = var.eks_node_group_capacity_type
  disk_size      = var.eks_node_group_disk_size

  scaling_config {
    desired_size = var.eks_node_group_desired_size
    min_size     = var.eks_node_group_min_size
    max_size     = var.eks_node_group_max_size
  }

  update_config {
    max_unavailable = var.eks_node_group_update_config.max_unavailable
  }

  labels = var.eks_node_group_labels

  dynamic "taint" {
    for_each = var.eks_node_group_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  # Ensure cluster is ready before creating node group
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]

  tags = {
    Name = "${module.naming.id}-node-group-large"
  }
}

