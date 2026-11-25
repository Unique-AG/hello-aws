#######################################
# ALB for CloudFront VPC Origin
#######################################
#
# Creates an internal ALB that forwards traffic to the Ingress NLB.
# This ALB has security groups attached from creation (required for CloudFront VPC Origins).
# Architecture: CloudFront → ALB (with SGs) → Ingress NLB → ingress controller
#
# Reference: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html
#######################################

variable "alb_deletion_protection" {
  description = "Enable deletion protection for ALBs (recommended for production, disable for sbx teardown)"
  type        = bool
  default     = true
}

# Data source for CloudFront managed prefix list
# This prefix list contains all CloudFront edge server IP ranges
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Security Group for ALB (allows CloudFront traffic)
# This security group is attached during ALB creation
resource "aws_security_group" "alb_cloudfront" {
  #checkov:skip=CKV2_AWS_5: see docs/security-baseline.md
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id}-alb-cloudfront"
  description = "Security group for ALB used as CloudFront VPC Origin (forwards to Ingress NLB)"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${module.naming.id}-alb-cloudfront-sg"
  }
}

# Security Group Rules (separate resources to avoid limits)
# CloudFront creates this group when the VPC origin is created, so it cannot be
# looked up before then — hence the flag rather than an unconditional lookup.
data "aws_security_group" "cloudfront_vpc_origins" {
  count = var.enable_ingress_nlb && var.alb_ingress_from_cloudfront_service_sg ? 1 : 0

  vpc_id = aws_vpc.main.id

  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
}

# Narrower than the prefix list: that admits every CloudFront edge address,
# this admits only distributions reaching this VPC origin.
resource "aws_security_group_rule" "alb_cloudfront_https_ingress_service_sg" {
  count = var.enable_ingress_nlb && var.alb_ingress_from_cloudfront_service_sg ? 1 : 0

  type                     = "ingress"
  description              = "Allow HTTPS from the CloudFront VPC origin service security group"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.cloudfront_vpc_origins[0].id
  security_group_id        = aws_security_group.alb_cloudfront[0].id
}

resource "aws_security_group_rule" "alb_cloudfront_https_ingress" {
  count = var.enable_ingress_nlb && !var.alb_ingress_from_cloudfront_service_sg ? 1 : 0

  type              = "ingress"
  description       = "Allow HTTPS from CloudFront VPC Origin"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

# Note: HTTP ingress rule removed due to AWS security group rules limit
# CloudFront VPC Origin uses HTTPS to connect to the ALB
# The CloudFront managed prefix list contains many IP ranges that exceed the 60 rules limit

resource "aws_security_group_rule" "alb_cloudfront_https_egress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "egress"
  description       = "Allow HTTPS outbound to Ingress NLB"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

resource "aws_security_group_rule" "alb_cloudfront_http_egress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "egress"
  description       = "Allow HTTP outbound to Ingress NLB"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

# Internal ALB for CloudFront VPC Origin
# This ALB forwards traffic to the Ingress NLB
resource "aws_lb" "cloudfront" {
  #checkov:skip=CKV_AWS_91: see docs/security-baseline.md
  count = var.enable_ingress_nlb ? 1 : 0

  name               = "${module.naming.id_short}-cf-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_cloudfront[0].id]
  subnets            = aws_subnet.private[*].id

  enable_deletion_protection       = var.alb_deletion_protection
  drop_invalid_header_fields       = true
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${module.naming.id}-cloudfront-alb"
  }
}

# Target Group for Ingress NLB
# ALB forwards traffic to this target group, which points to the Ingress NLB IPs
# Note: ALB target groups cannot directly forward to NLB DNS names
# We use target_type = "ip" and resolve the NLB DNS to IP addresses
# Traffic: CloudFront (HTTPS) → ALB (TLS terminated) → Ingress NLB (HTTP:80) → ingress controller
resource "aws_lb_target_group" "ingress_nlb" {
  #checkov:skip=CKV_AWS_378: see docs/security-baseline.md
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id_short}-ing-nlb-tg"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id

  # Health check configuration
  # Ingress controller returns 404 on root path when no route is configured, so we accept 404
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-404"
  }

  # Note: preserve_client_ip is not supported for HTTPS target groups

  # Deregistration delay
  deregistration_delay = 30

  tags = {
    Name = "${module.naming.id}-ingress-nlb-tg"
  }
}

# The Ingress NLB has one ENI per private subnet. Counting subnets keeps the count
# known at plan time; each ENI's IP is read once the NLB exists.
locals {
  ingress_nlb_eni_count = var.enable_ingress_nlb ? length(aws_subnet.private) : 0
}

data "aws_network_interface" "ingress_nlb" {
  count = local.ingress_nlb_eni_count

  filter {
    name   = "description"
    values = ["ELB net/${module.naming.id_short}-ingress-nlb/*"]
  }

  filter {
    name   = "subnet-id"
    values = [aws_subnet.private[count.index].id]
  }

  depends_on = [aws_lb.ingress_nlb]
}

resource "aws_lb_target_group_attachment" "ingress_nlb" {
  count = local.ingress_nlb_eni_count

  target_group_arn = aws_lb_target_group.ingress_nlb[0].arn
  target_id        = data.aws_network_interface.ingress_nlb[count.index].private_ip
  port             = 80
}

#######################################
# ACM Certificate for Internal ALB
#######################################
# Certificate for TLS termination on the internal ALB
# This certificate validates the ALB for CloudFront VPC Origin connections

variable "internal_alb_certificate_domain" {
  description = "Domain name for the internal ALB certificate (e.g., '*.sbx.example.com')"
  type        = string
  default     = null
}

resource "aws_acm_certificate" "internal_alb" {
  count = var.enable_ingress_nlb && var.internal_alb_certificate_domain != null ? 1 : 0

  domain_name       = var.internal_alb_certificate_domain
  validation_method = "DNS"

  tags = {
    Name = "${module.naming.id}-internal-alb-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS Listener for ALB
# Listens on port 443 and forwards to Ingress NLB target group
# Only created when ACM certificate is configured (HTTPS listeners require a certificate)
resource "aws_lb_listener" "cloudfront_https" {
  count = var.enable_ingress_nlb && var.internal_alb_certificate_domain != null ? 1 : 0

  load_balancer_arn = aws_lb.cloudfront[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.internal_alb[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_nlb[0].arn
  }

  depends_on = [aws_lb.cloudfront, aws_lb_target_group.ingress_nlb, aws_acm_certificate.internal_alb]
}

# HTTP Listener (forwards to Ingress NLB)
