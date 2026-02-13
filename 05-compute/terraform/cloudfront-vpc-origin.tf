#######################################
# CloudFront VPC Origin
#######################################
#
# Creates a CloudFront VPC Origin for the internal ALB
# and shares it with the connectivity account via AWS RAM
#
# Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_vpc_origin
#######################################

# CloudFront VPC Origin Configuration
#
# This configuration creates a CloudFront VPC Origin for the internal ALB.
# Use enable_cloudfront_vpc_origin = true after the ALB is deployed.
#
# Two-phase deployment:
#   1. First deploy with enable_cloudfront_vpc_origin = false (creates ALB)
#   2. Then set enable_cloudfront_vpc_origin = true (creates VPC Origin)
#
variable "enable_cloudfront_vpc_origin" {
  description = "Whether to create CloudFront VPC Origin. Set to true after ALB is deployed (avoids circular dependency)."
  type        = bool
  default     = false
}

variable "internal_alb_arn_override" {
  description = "Optional: Internal ALB ARN for VPC Origin creation. If not provided, uses the CloudFront ALB created by alb-cloudfront.tf."
  type        = string
  default     = null
}

# Discover ALBs created by AWS Load Balancer Controller
# This data source is evaluated at apply time, so it will find ALBs that exist
# at that point. If no ALBs exist yet, the VPC Origin creation will be skipped.
data "aws_lbs" "internal_albs" {
  tags = {
    "elbv2.k8s.aws/cluster" = aws_eks_cluster.main.name
  }

  # Ensure EKS cluster and node group are ready before discovering ALBs
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
}

# Get details for each discovered ALB to filter for internal scheme
# Skip this data source if no override is provided and ALBs are unknown
# This avoids plan-time errors when ALBs don't exist yet
data "aws_lb" "alb_details" {
  # Only create data sources if override is provided (known at plan time)
  # Otherwise, skip and let the CloudFront resource handle the conditional creation
  count = var.internal_alb_arn_override != null ? 1 : 0
  arn   = var.internal_alb_arn_override

  depends_on = [data.aws_lbs.internal_albs]
}

locals {
  # Find internal ALB from discovered ALBs
  # Priority: 1. ALB created for CloudFront (alb-cloudfront.tf), 2. Override ARN, 3. Auto-discovered ALBs
  # If CloudFront ALB exists, use it; otherwise use override or auto-discovery
  internal_alb_arn = length(aws_lb.cloudfront) > 0 ? aws_lb.cloudfront[0].arn : (
    var.internal_alb_arn_override != null ? var.internal_alb_arn_override : null
  )

  internal_alb_dns_name = length(aws_lb.cloudfront) > 0 ? aws_lb.cloudfront[0].dns_name : (
    local.internal_alb_arn != null && length(data.aws_lb.alb_details) > 0 ? try(
      data.aws_lb.alb_details[0].dns_name, null
    ) : null
  )
}

# Create CloudFront VPC Origin using native Terraform resource
# Uses boolean variable to avoid circular dependency with ALB ARN
resource "aws_cloudfront_vpc_origin" "internal_alb" {
  count = var.enable_cloudfront_vpc_origin ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${module.naming.id}-cloudfront-alb"
    arn                    = local.internal_alb_arn
    http_port              = 80 # Required by API, but not used when origin_protocol_policy = "https-only"
    https_port             = 443
    origin_protocol_policy = "https-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(local.tags, {
    Name = "${module.naming.id}-vpc-origin"
  })

  # Ensure EKS cluster, node group, ALB discovery, and CloudFront ALB are complete before creating VPC Origin
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main,
    data.aws_lbs.internal_albs,
    data.aws_lb.alb_details,
    aws_lb.cloudfront
  ]
}

# Share VPC Origin with connectivity account via AWS RAM
# IMPORTANT: CloudFront VPC Origins are GLOBAL resources - RAM sharing MUST be in us-east-1
resource "aws_ram_resource_share" "vpc_origin" {
  count                     = var.enable_cloudfront_vpc_origin ? 1 : 0
  provider                  = aws.us_east_1
  name                      = "${module.naming.id}-cloudfront-vpc-origin-share"
  allow_external_principals = false

  tags = merge(local.tags, {
    Name = "${module.naming.id}-vpc-origin-share"
  })

  depends_on = [aws_cloudfront_vpc_origin.internal_alb]
}

# Add VPC Origin to resource share (must be in us-east-1 for global CloudFront resources)
resource "aws_ram_resource_association" "vpc_origin" {
  count              = var.enable_cloudfront_vpc_origin ? 1 : 0
  provider           = aws.us_east_1
  resource_arn       = aws_cloudfront_vpc_origin.internal_alb[0].arn
  resource_share_arn = aws_ram_resource_share.vpc_origin[0].arn

  depends_on = [
    aws_cloudfront_vpc_origin.internal_alb,
    aws_ram_resource_share.vpc_origin
  ]
}

# Share with connectivity account (must be in us-east-1)
resource "aws_ram_principal_association" "connectivity_account" {
  count              = var.enable_cloudfront_vpc_origin && var.connectivity_account_id != null ? 1 : 0
  provider           = aws.us_east_1
  principal          = var.connectivity_account_id
  resource_share_arn = aws_ram_resource_share.vpc_origin[0].arn

  depends_on = [
    aws_cloudfront_vpc_origin.internal_alb,
    aws_ram_resource_share.vpc_origin,
    aws_ram_resource_association.vpc_origin
  ]
}
