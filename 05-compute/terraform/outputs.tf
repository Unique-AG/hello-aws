#######################################
# Outputs
#######################################
#
# Output values for the compute layer.
# These can be referenced by other layers or external systems.
#######################################

# EKS Cluster Outputs
output "eks_cluster_id" {
  description = "ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "eks_node_group_id" {
  description = "ID of the EKS node group"
  value       = aws_eks_node_group.main.id
}

output "eks_node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.main.arn
}

# ECR Repository Outputs
output "ecr_repository_urls" {
  description = "Map of ECR repository names to repository URLs"
  value = {
    for repo in var.ecr_repositories : repo.name => aws_ecr_repository.main[repo.name].repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map of ECR repository names to repository ARNs"
  value = {
    for repo in var.ecr_repositories : repo.name => aws_ecr_repository.main[repo.name].arn
  }
}

# ECR Pull Through Cache Outputs
output "ecr_pull_through_cache_registry_urls" {
  description = "Map of pull-through cache registry prefixes to ECR registry URLs for pulling cached images"
  value = {
    for prefix in var.ecr_pull_through_cache_upstream_registries : prefix => "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${prefix}"
  }
}

output "ecr_registry_url" {
  description = "Base ECR registry URL (e.g., 123456789012.dkr.ecr.eu-central-2.amazonaws.com)"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_pull_through_cache_rule_ids" {
  description = "Map of pull-through cache registry prefixes to rule IDs"
  value = {
    for prefix, rule in aws_ecr_pull_through_cache_rule.main : prefix => rule.id
  }
}

# Azure Container Registry Outputs
output "acr_secret_arn" {
  description = "ARN of the Secrets Manager secret containing ACR credentials"
  value       = var.acr_registry_url != "" ? try(aws_secretsmanager_secret.acr_credentials[0].arn, null) : null
}

output "acr_pull_through_cache_url" {
  description = "ECR pull-through cache URL for Azure Container Registry"
  value       = var.acr_registry_url != "" ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.acr_registry_url}" : null
}

# ECR Image Scanning Outputs
output "ecr_scanning_configuration_scan_type" {
  description = "ECR registry scanning type (BASIC or ENHANCED)"
  value       = aws_ecr_registry_scanning_configuration.main.scan_type
}

output "ecr_image_scan_event_rule_arn" {
  description = "ARN of the EventBridge rule for ECR image scan findings"
  value       = aws_cloudwatch_event_rule.ecr_image_scan.arn
}

# AWS Account and Region
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Pod Identity Role Outputs
output "pod_identity_ebs_csi_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = aws_iam_role.ebs_csi.arn
}

output "pod_identity_cluster_secrets_role_arn" {
  description = "IAM role ARN for cluster secrets service account"
  value       = aws_iam_role.cluster_secrets.arn
}

output "pod_identity_assistants_core_role_arn" {
  description = "IAM role ARN for Assistants Core service"
  value       = aws_iam_role.assistants_core.arn
}

output "pod_identity_cert_manager_route53_role_arn" {
  description = "IAM role ARN for cert-manager Route 53 DNS-01 validation"
  value       = aws_iam_role.cert_manager_route53.arn
}

output "pod_identity_litellm_role_arn" {
  description = "IAM role ARN for LiteLLM proxy"
  value       = aws_iam_role.litellm.arn
}

output "pod_identity_ingestion_role_arn" {
  description = "IAM role ARN for ingestion service"
  value       = aws_iam_role.ingestion.arn
}

output "pod_identity_ingestion_worker_role_arn" {
  description = "IAM role ARN for ingestion-worker service"
  value       = aws_iam_role.ingestion_worker.arn
}

output "pod_identity_speech_role_arn" {
  description = "IAM role ARN for speech service"
  value       = aws_iam_role.speech.arn
}

# ALB Outputs (for external CloudFront/connectivity setup)
# These outputs help external systems discover ALBs created by AWS Load Balancer Controller

output "eks_cluster_name_for_alb_discovery" {
  description = "EKS cluster name - use this value as a variable in connectivity layer to discover ALBs by tag. Since there's NO Terraform state connection, provide this value manually or via naming convention. Example: data.aws_lbs with tags = { 'elbv2.k8s.aws/cluster' = this_value }"
  value       = aws_eks_cluster.main.name
}

# Note: ALB DNS names are dynamic and created by AWS Load Balancer Controller
# Since there's NO Terraform state connection between connectivity and hello-aws:
# 1. Get the cluster name from this output (manually or via naming convention)
# 2. In connectivity layer, use it as a variable:
#    variable "eks_cluster_name" { default = "eks-uq-dogfood-sbx-euc2" }
# 3. Discover ALBs via AWS API (no state dependency):
#    data "aws_lbs" "eks_albs" {
#      tags = { "elbv2.k8s.aws/cluster" = var.eks_cluster_name }
#    }

# CloudFront VPC Origin Outputs
output "cloudfront_vpc_origin_id" {
  description = "ID of the CloudFront VPC Origin (for use in connectivity layer)"
  value       = try(aws_cloudfront_vpc_origin.internal_alb[0].id, null)
}

output "cloudfront_vpc_origin_arn" {
  description = "ARN of the CloudFront VPC Origin"
  value       = try(aws_cloudfront_vpc_origin.internal_alb[0].arn, null)
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB (for CloudFront VPC Origin endpoint configuration)"
  value       = try(local.internal_alb_dns_name, null)
}

# ALB for CloudFront Outputs
output "cloudfront_alb_arn" {
  description = "ARN of the ALB created for CloudFront VPC Origin"
  value       = try(aws_lb.cloudfront[0].arn, null)
}

output "cloudfront_alb_dns_name" {
  description = "DNS name of the ALB created for CloudFront VPC Origin"
  value       = try(aws_lb.cloudfront[0].dns_name, null)
}

output "cloudfront_alb_security_group_id" {
  description = "Security group ID of the ALB created for CloudFront VPC Origin"
  value       = try(aws_security_group.alb_cloudfront[0].id, null)
}

# WebSocket ALB Outputs (public ALB for CloudFront standard origin)
output "websocket_alb_dns_name" {
  description = "DNS name of the public WebSocket ALB (for CloudFront standard origin)"
  value       = try(aws_lb.websocket[0].dns_name, null)
}

# VPC Endpoints
output "eks_endpoint_id" {
  description = "ID of the EKS Interface Endpoint"
  value       = var.enable_eks_endpoint ? aws_vpc_endpoint.eks[0].id : null
}

