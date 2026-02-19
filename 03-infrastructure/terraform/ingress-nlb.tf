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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingress-nlb-sg"
  })
}

# Allow inbound HTTP from VPC (ALBs forward to NLB on port 80)
resource "aws_security_group_rule" "ingress_nlb_http_ingress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "ingress"
  description       = "Allow HTTP from VPC (ALBs)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.ingress_nlb[0].id
}

# Allow inbound HTTPS from VPC (ALBs forward to NLB on port 443)
resource "aws_security_group_rule" "ingress_nlb_https_ingress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "ingress"
  description       = "Allow HTTPS from VPC (ALBs)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.ingress_nlb[0].id
}

# Allow outbound to EKS pods (VPC CIDR covers pod IPs in private subnets)
resource "aws_security_group_rule" "ingress_nlb_egress" {
  count = var.enable_ingress_nlb ? 1 : 0

  type              = "egress"
  description       = "Allow outbound to EKS pods"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.main.cidr_block]
  security_group_id = aws_security_group.ingress_nlb[0].id
}

#######################################
# Network Load Balancer
#######################################

resource "aws_lb" "ingress_nlb" {
  #checkov:skip=CKV_AWS_91: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_150: Deletion protection controlled by var.alb_deletion_protection; disabled in sandbox
  count = var.enable_ingress_nlb ? 1 : 0

  name               = "${module.naming.id_short}-ingress-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.ingress_nlb[0].id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingress-nlb"
  })
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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingress-http-tg"
  })
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

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ingress-https-tg"
  })
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
