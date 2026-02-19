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
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id}-alb-cloudfront"
  description = "Security group for ALB used as CloudFront VPC Origin (forwards to Ingress NLB)"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${module.naming.id}-alb-cloudfront-sg"
  })
}

# Security Group Rules (separate resources to avoid limits)
resource "aws_security_group_rule" "alb_cloudfront_https_ingress" {
  count = var.enable_ingress_nlb ? 1 : 0

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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-cloudfront-alb"
  })
}

# Target Group for Ingress NLB
# ALB forwards traffic to this target group, which points to the Ingress NLB IPs
# Note: ALB target groups cannot directly forward to NLB DNS names
# We use target_type = "ip" and resolve the NLB DNS to IP addresses
# Traffic: CloudFront (HTTPS) → ALB (TLS terminated) → Ingress NLB (HTTP:80) → ingress controller
resource "aws_lb_target_group" "ingress_nlb" {
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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingress-nlb-tg"
  })
}

# Resolve Ingress NLB DNS to IP addresses and register as targets
# NLB DNS resolves to one IP per AZ - these are stable for NLBs
data "dns_a_record_set" "ingress_nlb" {
  count = var.enable_ingress_nlb ? 1 : 0
  host  = aws_lb.ingress_nlb[0].dns_name
}

resource "aws_lb_target_group_attachment" "ingress_nlb" {
  for_each = var.enable_ingress_nlb ? toset(data.dns_a_record_set.ingress_nlb[0].addrs) : toset([])

  target_group_arn = aws_lb_target_group.ingress_nlb[0].arn
  target_id        = each.value
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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-internal-alb-cert"
  })

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
# CloudFront handles TLS termination, so HTTP is sufficient for VPC Origin
resource "aws_lb_listener" "cloudfront_http" {
  #checkov:skip=CKV_AWS_2: see docs/security-baseline.md
  #trivy:ignore:AVD-AWS-0054 CloudFront handles TLS termination; HTTP is sufficient for VPC Origin
  count = var.enable_ingress_nlb ? 1 : 0

  load_balancer_arn = aws_lb.cloudfront[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_nlb[0].arn
  }

  depends_on = [aws_lb.cloudfront, aws_lb_target_group.ingress_nlb]
}

#######################################
# Public ALB for WebSocket Traffic
#######################################
#
# Creates a public ALB restricted to CloudFront-only traffic (via managed prefix list SG)
# as a standard CloudFront custom origin for WebSocket paths.
# CloudFront VPC Origins do NOT support WebSocket, so this public ALB bypasses VPC Origin.
# Architecture: CloudFront → Standard Origin → Public ALB → Ingress NLB → Ingress Controller → Chat Backend
#######################################

# Security Group for Public WebSocket ALB (allows CloudFront traffic only)
resource "aws_security_group" "alb_websocket" {
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id}-alb-websocket"
  description = "Security group for public WebSocket ALB (CloudFront IPs only)"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${module.naming.id}-alb-websocket-sg"
  })
}

resource "aws_security_group_rule" "alb_websocket_https_ingress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "ingress"
  description       = "Allow HTTPS from CloudFront edge servers"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb_websocket[0].id
}

resource "aws_security_group_rule" "alb_websocket_http_egress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "egress"
  description       = "Allow HTTP outbound to Ingress NLB"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.alb_websocket[0].id
}

# Public ALB for WebSocket traffic
resource "aws_lb" "websocket" {
  #checkov:skip=CKV_AWS_91: see docs/security-baseline.md
  #trivy:ignore:AVD-AWS-0053 Public-facing by design for WebSocket traffic from clients
  count = var.enable_ingress_nlb ? 1 : 0

  name               = "${module.naming.id_short}-ws-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_websocket[0].id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection       = var.alb_deletion_protection
  drop_invalid_header_fields       = true
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = merge(local.tags, {
    Name = "${module.naming.id}-websocket-alb"
  })
}

# Target Group for WebSocket ALB → Ingress NLB
resource "aws_lb_target_group" "websocket_ingress" {
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id_short}-ws-ing-tg"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id

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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ws-ingress-tg"
  })
}

# Register Ingress NLB IPs as targets for WebSocket ALB
resource "aws_lb_target_group_attachment" "websocket_ingress" {
  for_each = var.enable_ingress_nlb ? toset(data.dns_a_record_set.ingress_nlb[0].addrs) : toset([])

  target_group_arn = aws_lb_target_group.websocket_ingress[0].arn
  target_id        = each.value
  port             = 80
}

# HTTPS Listener for WebSocket ALB
resource "aws_lb_listener" "websocket_https" {
  count = var.enable_ingress_nlb && var.internal_alb_certificate_domain != null ? 1 : 0

  load_balancer_arn = aws_lb.websocket[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.internal_alb[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket_ingress[0].arn
  }

  depends_on = [aws_lb.websocket, aws_lb_target_group.websocket_ingress, aws_acm_certificate.internal_alb]
}

# HTTP → HTTPS redirect for WebSocket ALB
resource "aws_lb_listener" "websocket_http" {
  count = var.enable_ingress_nlb ? 1 : 0

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
