output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

# VPC Flow Log Outputs
output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = aws_flow_log.main.id
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch Log Group for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

# Internet Gateway Outputs
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.public[*].cidr_block
}

# Private Subnet Outputs
output "private_subnet_ids" {
  description = "IDs of the private subnets (for workloads: EKS, compute, AI, monitoring)"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

# Isolated Subnet Outputs
output "isolated_subnet_ids" {
  description = "IDs of the isolated subnets (for databases: RDS, ElastiCache)"
  value       = aws_subnet.isolated[*].id
}

output "isolated_subnet_cidrs" {
  description = "CIDR blocks of the isolated subnets"
  value       = aws_subnet.isolated[*].cidr_block
}

# NAT Gateway Outputs
output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IP addresses of the NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

# Route Table Outputs
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "isolated_route_table_ids" {
  description = "IDs of the isolated route tables"
  value       = aws_route_table.isolated[*].id
}

# Availability Zones
output "availability_zones" {
  description = "Availability zones used for subnets"
  value       = local.availability_zones
}

# AWS Region
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# VPC Endpoint Outputs
output "s3_gateway_endpoint_id" {
  description = "ID of the S3 Gateway Endpoint"
  value       = var.enable_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].id : null
}

output "kms_endpoint_id" {
  description = "ID of the KMS Interface Endpoint"
  value       = var.enable_kms_endpoint ? aws_vpc_endpoint.kms[0].id : null
}

output "secrets_manager_endpoint_id" {
  description = "ID of the Secrets Manager Interface Endpoint"
  value       = var.enable_secrets_manager_endpoint ? aws_vpc_endpoint.secrets_manager[0].id : null
}

output "ecr_api_endpoint_id" {
  description = "ID of the ECR API Interface Endpoint"
  value       = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "ecr_dkr_endpoint_id" {
  description = "ID of the ECR Docker Registry Interface Endpoint"
  value       = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

output "cloudwatch_logs_endpoint_id" {
  description = "ID of the CloudWatch Logs Interface Endpoint"
  value       = var.enable_cloudwatch_endpoints ? aws_vpc_endpoint.cloudwatch_logs[0].id : null
}

output "cloudwatch_metrics_endpoint_id" {
  description = "ID of the CloudWatch Metrics Interface Endpoint"
  value       = var.enable_cloudwatch_endpoints ? aws_vpc_endpoint.cloudwatch_metrics[0].id : null
}

output "prometheus_endpoint_id" {
  description = "ID of the Managed Prometheus Interface Endpoint"
  value       = var.enable_prometheus_endpoint ? aws_vpc_endpoint.prometheus[0].id : null
}

output "bedrock_endpoint_id" {
  description = "ID of the Bedrock Interface Endpoint"
  value       = var.enable_bedrock_endpoint ? aws_vpc_endpoint.bedrock[0].id : null
}

output "bedrock_runtime_endpoint_id" {
  description = "ID of the Bedrock Runtime Interface Endpoint"
  value       = var.enable_bedrock_endpoint ? aws_vpc_endpoint.bedrock_runtime[0].id : null
}

# Note: EKS, RDS, and ElastiCache endpoints are now defined in their respective layers:
# - EKS endpoint: 05-compute/terraform/vpc-endpoints.tf
# - RDS and ElastiCache endpoints: 04-data-and-ai/terraform/vpc-endpoints.tf

output "sts_endpoint_id" {
  description = "ID of the STS Interface Endpoint (required for IRSA)"
  value       = var.enable_sts_endpoint ? aws_vpc_endpoint.sts[0].id : null
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group for VPC interface endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

# Route 53 Outputs
output "route53_private_zone_id" {
  description = "Zone ID of the Route 53 Private Hosted Zone (for use in other layers)"
  value       = var.route53_private_zone_id
}

output "route53_private_zone_domain" {
  description = "Domain name of the Route 53 Private Hosted Zone (for use in other layers)"
  value       = var.route53_private_zone_domain
}

# KMS Key Outputs
output "kms_key_general_arn" {
  description = "ARN of the general encryption KMS key (for EKS, EBS, S3, RDS, ElastiCache, ECR)"
  value       = aws_kms_key.general.arn
}

output "kms_key_general_id" {
  description = "ID of the general encryption KMS key"
  value       = aws_kms_key.general.key_id
}

output "kms_key_secrets_manager_arn" {
  description = "ARN of the Secrets Manager KMS key"
  value       = aws_kms_key.secrets_manager.arn
}

output "kms_key_secrets_manager_id" {
  description = "ID of the Secrets Manager KMS key"
  value       = aws_kms_key.secrets_manager.key_id
}

output "kms_key_cloudwatch_logs_arn" {
  description = "ARN of the CloudWatch Logs KMS key"
  value       = aws_kms_key.cloudwatch_logs.arn
}

output "kms_key_cloudwatch_logs_id" {
  description = "ID of the CloudWatch Logs KMS key"
  value       = aws_kms_key.cloudwatch_logs.key_id
}

output "kms_key_prometheus_arn" {
  description = "ARN of the Managed Prometheus KMS key (for use by data-and-ai layer)"
  value       = var.enable_managed_prometheus ? aws_kms_key.prometheus[0].arn : null
}

output "kms_key_prometheus_id" {
  description = "ID of the Managed Prometheus KMS key (for use by data-and-ai layer)"
  value       = var.enable_managed_prometheus ? aws_kms_key.prometheus[0].key_id : null
}

# SNS Alerts Output
output "sns_topic_alerts_arn" {
  description = "ARN of the SNS topic for infrastructure alerts"
  value       = aws_sns_topic.alerts.arn
}

# Monitoring Outputs
output "cloudwatch_log_group_infrastructure_name" {
  description = "Name of the infrastructure CloudWatch log group"
  value       = aws_cloudwatch_log_group.infrastructure.name
}

output "cloudwatch_log_group_infrastructure_arn" {
  description = "ARN of the infrastructure CloudWatch log group (for use by data-and-ai layer)"
  value       = aws_cloudwatch_log_group.infrastructure.arn
}

output "ssm_instance_profile_arn" {
  description = "ARN of the IAM instance profile for Session Manager access"
  value       = aws_iam_instance_profile.ssm_instance.arn
}

output "ssm_instance_role_arn" {
  description = "ARN of the IAM role for Session Manager access"
  value       = aws_iam_role.ssm_instance.arn
}

output "ssm_instance_profile_name" {
  description = "Name of the IAM instance profile for Session Manager access"
  value       = aws_iam_instance_profile.ssm_instance.name
}

output "management_server_instance_id" {
  description = "Instance ID of the management server (if enabled)"
  value       = var.enable_management_server ? aws_instance.management_server[0].id : null
}

output "management_server_private_ip" {
  description = "Private IP address of the management server"
  value       = var.enable_management_server ? aws_instance.management_server[0].private_ip : null
}

output "management_server_public_ip" {
  description = "Public IP address of the management server (if public access enabled)"
  value       = var.enable_management_server && var.management_server_public_access ? aws_eip.management_server[0].public_ip : null
}

output "management_server_security_group_id" {
  description = "Security group ID for the management server"
  value       = aws_security_group.management_server.id
}

# VPC Endpoint Outputs
output "ec2_endpoint_id" {
  description = "ID of the EC2 Interface Endpoint"
  value       = var.enable_ec2_endpoint ? aws_vpc_endpoint.ec2[0].id : null
}

# SSM Endpoint Outputs
output "ssm_endpoint_id" {
  description = "ID of the SSM Interface Endpoint"
  value       = var.enable_ssm_endpoints ? aws_vpc_endpoint.ssm[0].id : null
}

output "ssm_messages_endpoint_id" {
  description = "ID of the SSM Messages Interface Endpoint"
  value       = var.enable_ssm_endpoints ? aws_vpc_endpoint.ssm_messages[0].id : null
}

output "ec2_messages_endpoint_id" {
  description = "ID of the EC2 Messages Interface Endpoint"
  value       = var.enable_ssm_endpoints ? aws_vpc_endpoint.ec2_messages[0].id : null
}

# Transit Gateway Outputs
output "transit_gateway_attachment_id" {
  description = "ID of the Transit Gateway VPC attachment"
  value       = try(aws_ec2_transit_gateway_vpc_attachment.main[0].id, null)
}

output "transit_gateway_attachment_arn" {
  description = "ARN of the Transit Gateway VPC attachment"
  value       = try(aws_ec2_transit_gateway_vpc_attachment.main[0].arn, null)
}

# Cross-Account IAM Outputs
output "connectivity_account_role_arn" {
  description = "ARN of the IAM role that allows the connectivity account to discover resources"
  value       = try(aws_iam_role.connectivity_account[0].arn, null)
}

