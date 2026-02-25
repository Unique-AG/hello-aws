#######################################
# Ingress NLB (Terraform-managed)
#######################################
#
# Creates an internal NLB for ingress controller traffic.
# Target groups use IP target type — the AWS Load Balancer Controller
# registers ingress controller pod IPs via TargetGroupBinding (no ASG attachment needed).
#
# Architecture: CloudFront → ALB (with SGs) → Ingress NLB → Ingress controller pods (via TargetGroupBinding)
#
#######################################

variable "enable_ingress_nlb" {
  description = "Whether to create the Terraform-managed ingress NLB and associated resources"
  type        = bool
  default     = true
}

#######################################
# Security Group
#######################################

resource "aws_security_group" "ingress_nlb" {
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id}-ingress-nlb"
  description = "Security group for ingress NLB (inbound from ALBs, outbound to EKS pods)"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${module.naming.id}-ingress-nlb-sg"
  }
}

# Allow inbound HTTP from CloudFront ALB
resource "aws_security_group_rule" "ingress_nlb_http_from_cloudfront_alb" {
  count = var.enable_ingress_nlb ? 1 : 0

  type                     = "ingress"
  description              = "Allow HTTP from CloudFront ALB"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_cloudfront[0].id
  security_group_id        = aws_security_group.ingress_nlb[0].id
}

# Allow inbound HTTP from WebSocket ALB
resource "aws_security_group_rule" "ingress_nlb_http_from_websocket_alb" {
  count = var.enable_ingress_nlb ? 1 : 0

  type                     = "ingress"
  description              = "Allow HTTP from WebSocket ALB"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_websocket[0].id
  security_group_id        = aws_security_group.ingress_nlb[0].id
}

# Allow inbound HTTPS from CloudFront ALB
resource "aws_security_group_rule" "ingress_nlb_https_from_cloudfront_alb" {
  count = var.enable_ingress_nlb ? 1 : 0

  type                     = "ingress"
  description              = "Allow HTTPS from CloudFront ALB"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_cloudfront[0].id
  security_group_id        = aws_security_group.ingress_nlb[0].id
}

# Allow inbound HTTPS from WebSocket ALB
resource "aws_security_group_rule" "ingress_nlb_https_from_websocket_alb" {
  count = var.enable_ingress_nlb ? 1 : 0

  type                     = "ingress"
  description              = "Allow HTTPS from WebSocket ALB"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_websocket[0].id
  security_group_id        = aws_security_group.ingress_nlb[0].id
}

# TODO: Transit Gateway ingress — restrict to TGW CIDRs in the next PR (hardening pass)

# Allow outbound to EKS pods (primary + secondary CIDR when pod networking uses RFC 6598 range)
resource "aws_vpc_security_group_egress_rule" "ingress_nlb_to_pods" {
  for_each = var.enable_ingress_nlb ? toset(
    var.enable_secondary_cidr ? [aws_vpc.main.cidr_block, local.secondary_cidr] : [aws_vpc.main.cidr_block]
  ) : toset([])

  security_group_id = aws_security_group.ingress_nlb[0].id
  description       = "Allow outbound to EKS pods (${each.value})"
  from_port         = 0
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

#######################################
# Network Load Balancer
#######################################

resource "aws_lb" "ingress_nlb" {
  #checkov:skip=CKV_AWS_91: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_150: see docs/security-baseline.md
  count = var.enable_ingress_nlb ? 1 : 0

  name               = "${module.naming.id_short}-ingress-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.ingress_nlb[0].id]

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${module.naming.id}-ingress-nlb"
  }
}

#######################################
# Target Groups (IP target type)
#######################################
# AWS Load Balancer Controller manages target registration
# via TargetGroupBinding CRDs — no static targets needed here.

resource "aws_lb_target_group" "ingress_http" {
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id_short}-ing-http"
  port        = 80
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    protocol            = "TCP"
  }

  deregistration_delay = 30

  tags = {
    Name = "${module.naming.id}-ingress-http-tg"
  }
}

resource "aws_lb_target_group" "ingress_https" {
  count = var.enable_ingress_nlb ? 1 : 0

  name        = "${module.naming.id_short}-ing-https"
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    protocol            = "TCP"
  }

  deregistration_delay = 30

  tags = {
    Name = "${module.naming.id}-ingress-https-tg"
  }
}

#######################################
# Listeners
#######################################

resource "aws_lb_listener" "ingress_http" {
  count = var.enable_ingress_nlb ? 1 : 0

  load_balancer_arn = aws_lb.ingress_nlb[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http[0].arn
  }
}

resource "aws_lb_listener" "ingress_https" {
  count = var.enable_ingress_nlb ? 1 : 0

  load_balancer_arn = aws_lb.ingress_nlb[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_https[0].arn
  }
}
