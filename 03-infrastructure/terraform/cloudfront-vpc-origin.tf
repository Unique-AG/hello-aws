#######################################
# CloudFront VPC Origin
#######################################
#
# Creates a CloudFront VPC Origin for the internal ALB
# and shares it with the connectivity account via AWS RAM
#
# Reference: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_vpc_origin
#######################################

variable "enable_cloudfront_vpc_origin" {
  description = "Whether to create CloudFront VPC Origin. Requires enable_ingress_nlb = true (ALB must exist)."
  type        = bool
  default     = false
}

# Create CloudFront VPC Origin using native Terraform resource
resource "aws_cloudfront_vpc_origin" "internal_alb" {
  count = var.enable_ingress_nlb && var.enable_cloudfront_vpc_origin ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${module.naming.id}-cloudfront-alb"
    arn                    = aws_lb.cloudfront[0].arn
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

  depends_on = [aws_lb.cloudfront]
}

# Share VPC Origin with connectivity account via AWS RAM
# IMPORTANT: CloudFront VPC Origins are GLOBAL resources - RAM sharing MUST be in us-east-1
resource "aws_ram_resource_share" "vpc_origin" {
  count                     = var.enable_ingress_nlb && var.enable_cloudfront_vpc_origin ? 1 : 0
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
  count              = var.enable_ingress_nlb && var.enable_cloudfront_vpc_origin ? 1 : 0
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
  count              = var.enable_ingress_nlb && var.enable_cloudfront_vpc_origin && var.connectivity_account_id != null ? 1 : 0
  provider           = aws.us_east_1
  principal          = var.connectivity_account_id
  resource_share_arn = aws_ram_resource_share.vpc_origin[0].arn

  depends_on = [
    aws_cloudfront_vpc_origin.internal_alb,
    aws_ram_resource_share.vpc_origin,
    aws_ram_resource_association.vpc_origin
  ]
}
