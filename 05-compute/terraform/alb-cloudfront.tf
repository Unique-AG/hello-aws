#######################################
# ALB for CloudFront VPC Origin
#######################################
#
# Creates an internal ALB that forwards traffic to the Kong NLB.
# This ALB has security groups attached from creation (required for CloudFront VPC Origins).
# Architecture: CloudFront → ALB (with SGs) → Kong NLB → Kong Gateway
#
# Reference: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html
#######################################

variable "kong_nlb_dns_name" {
  description = "DNS name of the Kong NLB to forward traffic to. Can be AWS-provided DNS or Private Hosted Zone DNS (e.g., kong-nlb.sbx.aws.unique.dev or ac07acf717701483c979dc6c7144664a-df35c4a149aa54be.elb.eu-central-2.amazonaws.com)"
  type        = string
  default     = null
}

variable "kong_nlb_security_group_id" {
  description = "Security group ID for the ALB (e.g., sg-0cecb4958cdae0338). Must be attached during ALB creation."
  type        = string
  default     = null
}

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
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  name        = "${module.naming.id}-alb-cloudfront"
  description = "Security group for ALB used as CloudFront VPC Origin (forwards to Kong NLB)"
  vpc_id      = local.infrastructure.vpc_id

  tags = {
    Name = "${module.naming.id}-alb-cloudfront-sg"
  }
}

# Note: HTTP ingress rule removed — CloudFront managed prefix list exceeds 60 rules limit
# CloudFront VPC Origin uses HTTPS to connect to the ALB

resource "aws_vpc_security_group_ingress_rule" "alb_cloudfront_https" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  security_group_id = aws_security_group.alb_cloudfront[0].id
  description       = "Allow HTTPS from CloudFront VPC Origin"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_cloudfront_https" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  security_group_id = aws_security_group.alb_cloudfront[0].id
  description       = "Allow HTTPS outbound to Kong NLB"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "alb_cloudfront_http" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  security_group_id = aws_security_group.alb_cloudfront[0].id
  description       = "Allow HTTP outbound to Kong NLB"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Internal ALB for CloudFront VPC Origin
# This ALB forwards traffic to the Kong NLB
resource "aws_lb" "cloudfront" {
  #checkov:skip=CKV_AWS_91: see docs/security-baseline.md
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  name               = "${module.naming.id_short}-cf-alb"
  internal           = true
  load_balancer_type = "application"
  # Attach CloudFront security group (allows CloudFront traffic)
  # Note: We don't attach the Kong NLB security group to avoid hitting security group rules limit
  security_groups = [aws_security_group.alb_cloudfront[0].id]
  subnets         = local.infrastructure.private_subnet_ids

  enable_deletion_protection       = var.alb_deletion_protection
  drop_invalid_header_fields       = true
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${module.naming.id}-cloudfront-alb"
  }
}

# Target Group for Kong NLB
# ALB forwards traffic to this target group, which points to the Kong NLB
# Note: ALB target groups cannot directly forward to NLB DNS names
# We'll use target_type = "ip" and resolve the NLB DNS to IP addresses
# Traffic: CloudFront (HTTPS) → ALB (TLS terminated) → Kong NLB (HTTP:80) → Kong Gateway
resource "aws_lb_target_group" "kong_nlb" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  name        = "${module.naming.id}-kong-nlb-tg"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.infrastructure.vpc_id

  # Health check configuration
  # Kong returns 404 on root path when no route is configured, so we accept 404
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
    Name = "${module.naming.id}-kong-nlb-tg"
  }
}

# Resolve Kong NLB DNS to IP addresses and register as targets
# NLB DNS resolves to one IP per AZ - these are stable for NLBs
data "dns_a_record_set" "kong_nlb" {
  count = var.kong_nlb_dns_name != null ? 1 : 0
  host  = var.kong_nlb_dns_name
}

resource "aws_lb_target_group_attachment" "kong_nlb" {
  for_each = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? toset(data.dns_a_record_set.kong_nlb[0].addrs) : toset([])

  target_group_arn = aws_lb_target_group.kong_nlb[0].arn
  target_id        = each.value
  port             = 80
}

#######################################
# ACM Certificate for Internal ALB
#######################################
# Certificate for TLS termination on the internal ALB
# This certificate validates the ALB for CloudFront VPC Origin connections

variable "internal_alb_certificate_domain" {
  description = "Domain name for the internal ALB certificate (e.g., '*.sbx.rbcn.ai')"
  type        = string
  default     = null
}

resource "aws_acm_certificate" "internal_alb" {
  count = var.kong_nlb_dns_name != null && var.internal_alb_certificate_domain != null ? 1 : 0

  domain_name       = var.internal_alb_certificate_domain
  validation_method = "DNS"

  tags = {
    Name = "${module.naming.id}-internal-alb-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Output the DNS validation records for manual/external validation
output "internal_alb_certificate_validation_records" {
  description = "DNS validation records for the internal ALB certificate (create these in Route 53 or external DNS)"
  value = var.kong_nlb_dns_name != null && var.internal_alb_certificate_domain != null ? {
    for dvo in aws_acm_certificate.internal_alb[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}
}

output "internal_alb_certificate_arn" {
  description = "ARN of the internal ALB certificate"
  value       = var.kong_nlb_dns_name != null && var.internal_alb_certificate_domain != null ? aws_acm_certificate.internal_alb[0].arn : null
}

# HTTPS Listener for ALB
# Listens on port 443 and forwards to Kong NLB target group
# Only created when ACM certificate is configured (HTTPS listeners require a certificate)
resource "aws_lb_listener" "cloudfront_https" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null && var.internal_alb_certificate_domain != null ? 1 : 0

  load_balancer_arn = aws_lb.cloudfront[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.internal_alb[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_nlb[0].arn
  }

  depends_on = [aws_lb.cloudfront, aws_lb_target_group.kong_nlb, aws_acm_certificate.internal_alb]
}

# HTTP Listener (forwards to Kong NLB)
# CloudFront handles TLS termination, so HTTP is sufficient for VPC Origin
resource "aws_lb_listener" "cloudfront_http" {
  #checkov:skip=CKV_AWS_2: see docs/security-baseline.md
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  load_balancer_arn = aws_lb.cloudfront[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_nlb[0].arn
  }

  depends_on = [aws_lb.cloudfront, aws_lb_target_group.kong_nlb]
}

#######################################
# Public ALB for WebSocket Traffic
#######################################
#
# Creates a public ALB restricted to CloudFront-only traffic (via managed prefix list SG)
# as a standard CloudFront custom origin for WebSocket paths.
# CloudFront VPC Origins do NOT support WebSocket, so this public ALB bypasses VPC Origin.
# Architecture: CloudFront → Standard Origin → Public ALB → Kong NLB → Kong → Chat Backend
#######################################

# Security Group for Public WebSocket ALB (allows CloudFront traffic only)
resource "aws_security_group" "alb_websocket" {
  count = var.kong_nlb_dns_name != null ? 1 : 0

  name        = "${module.naming.id}-alb-websocket"
  description = "Security group for public WebSocket ALB (CloudFront IPs only)"
  vpc_id      = local.infrastructure.vpc_id

  tags = {
    Name = "${module.naming.id}-alb-websocket-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_websocket_https" {
  count = var.kong_nlb_dns_name != null ? 1 : 0

  security_group_id = aws_security_group.alb_websocket[0].id
  description       = "Allow HTTPS from CloudFront edge servers"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_websocket_http" {
  count = var.kong_nlb_dns_name != null ? 1 : 0

  security_group_id = aws_security_group.alb_websocket[0].id
  description       = "Allow HTTP outbound to Kong NLB"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = local.infrastructure.vpc_cidr_block
}

# Public ALB for WebSocket traffic
resource "aws_lb" "websocket" {
  #checkov:skip=CKV_AWS_91: see docs/security-baseline.md
  count = var.kong_nlb_dns_name != null ? 1 : 0

  name               = "${module.naming.id_short}-ws-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_websocket[0].id]
  subnets            = local.infrastructure.public_subnet_ids

  enable_deletion_protection       = var.alb_deletion_protection
  drop_invalid_header_fields       = true
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${module.naming.id}-websocket-alb"
  }
}

# Target Group for WebSocket ALB → Kong NLB
resource "aws_lb_target_group" "websocket_kong" {
  count = var.kong_nlb_dns_name != null ? 1 : 0

  name        = "${module.naming.id}-ws-kong-tg"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.infrastructure.vpc_id

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

  deregistration_delay = 30

  tags = {
    Name = "${module.naming.id}-ws-kong-tg"
  }
}

# Register Kong NLB IPs as targets for WebSocket ALB
resource "aws_lb_target_group_attachment" "websocket_kong" {
  for_each = var.kong_nlb_dns_name != null ? toset(data.dns_a_record_set.kong_nlb[0].addrs) : toset([])

  target_group_arn = aws_lb_target_group.websocket_kong[0].arn
  target_id        = each.value
  port             = 80
}

# HTTPS Listener for WebSocket ALB
resource "aws_lb_listener" "websocket_https" {
  count = var.kong_nlb_dns_name != null && var.internal_alb_certificate_domain != null ? 1 : 0

  load_balancer_arn = aws_lb.websocket[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.internal_alb[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket_kong[0].arn
  }

  depends_on = [aws_lb.websocket, aws_lb_target_group.websocket_kong, aws_acm_certificate.internal_alb]
}

# HTTP → HTTPS redirect for WebSocket ALB
resource "aws_lb_listener" "websocket_http" {
  count = var.kong_nlb_dns_name != null ? 1 : 0

  load_balancer_arn = aws_lb.websocket[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  depends_on = [aws_lb.websocket]
}

