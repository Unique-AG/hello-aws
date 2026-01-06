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

  # Note: Rules are added via separate aws_security_group_rule resources
  # to avoid hitting AWS security group rules limit

  tags = merge(local.tags, {
    Name = "${module.naming.id}-alb-cloudfront-sg"
  })
}

# Security Group Rules (separate resources to avoid limits)
resource "aws_security_group_rule" "alb_cloudfront_https_ingress" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  type              = "ingress"
  description       = "Allow HTTPS from CloudFront VPC Origin"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

resource "aws_security_group_rule" "alb_cloudfront_http_ingress" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  type              = "ingress"
  description       = "Allow HTTP from CloudFront VPC Origin"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

resource "aws_security_group_rule" "alb_cloudfront_https_egress" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  type              = "egress"
  description       = "Allow HTTPS outbound to Kong NLB"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [local.infrastructure.vpc_cidr_block]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

resource "aws_security_group_rule" "alb_cloudfront_http_egress" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  type              = "egress"
  description       = "Allow HTTP outbound to Kong NLB"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [local.infrastructure.vpc_cidr_block]
  security_group_id = aws_security_group.alb_cloudfront[0].id
}

# Internal ALB for CloudFront VPC Origin
# This ALB forwards traffic to the Kong NLB
resource "aws_lb" "cloudfront" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  name               = "${module.naming.id_short}-cf-alb"
  internal           = true
  load_balancer_type = "application"
  # Attach CloudFront security group (allows CloudFront traffic)
  # Note: We don't attach the Kong NLB security group to avoid hitting security group rules limit
  security_groups = [aws_security_group.alb_cloudfront[0].id]
  subnets         = local.infrastructure.private_subnet_ids

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  # Access logs (optional - can be enabled later)
  # access_logs {
  #   bucket  = aws_s3_bucket.alb_logs.id
  #   prefix  = "alb-cloudfront"
  #   enabled = true
  # }

  tags = merge(local.tags, {
    Name = "${module.naming.id}-cloudfront-alb"
  })
}

# Target Group for Kong NLB
# ALB forwards traffic to this target group, which points to the Kong NLB
# Note: ALB target groups cannot directly forward to NLB DNS names
# We'll use target_type = "ip" and resolve the NLB DNS to IP addresses
resource "aws_lb_target_group" "kong_nlb" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  name        = "${module.naming.id}-kong-nlb-tg"
  target_type = "ip"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = local.infrastructure.vpc_id

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTPS"
    matcher             = "200-399"
  }

  # Note: preserve_client_ip is not supported for HTTPS target groups

  # Deregistration delay
  deregistration_delay = 30

  tags = merge(local.tags, {
    Name = "${module.naming.id}-kong-nlb-tg"
  })
}

# Resolve Kong NLB DNS to IP addresses and register as targets
# Note: NLB DNS resolves to multiple IPs (one per AZ)
# We'll resolve and register them dynamically
resource "null_resource" "register_kong_nlb_targets" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  triggers = {
    kong_nlb_dns     = var.kong_nlb_dns_name
    target_group_arn = aws_lb_target_group.kong_nlb[0].arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Resolve NLB DNS name (supports both AWS-provided DNS and Private Hosted Zone DNS)
      # The DNS name will resolve to multiple IP addresses (one per Availability Zone)
      echo "Resolving NLB DNS: ${var.kong_nlb_dns_name}"
      NLB_IPS=$(dig +short ${var.kong_nlb_dns_name} | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
      
      if [ -z "$NLB_IPS" ]; then
        echo "Error: Could not resolve ${var.kong_nlb_dns_name} to IP addresses"
        echo "Please verify the DNS name is correct and resolvable from this environment"
        exit 1
      fi
      
      echo "Found NLB IP addresses:"
      echo "$NLB_IPS" | while read IP; do echo "  - $IP"; done
      
      # Register each IP as a target
      REGISTERED_COUNT=0
      for IP in $NLB_IPS; do
        echo "Registering target: $IP:443"
        if aws elbv2 register-targets \
          --region ${var.aws_region} \
          --target-group-arn ${aws_lb_target_group.kong_nlb[0].arn} \
          --targets Id=$IP,Port=443 2>&1; then
          echo "  ✓ Successfully registered $IP:443"
          REGISTERED_COUNT=$((REGISTERED_COUNT + 1))
        else
          echo "  ⚠ Target $IP:443 may already be registered or registration failed"
        fi
      done
      
      echo "Registration complete: $REGISTERED_COUNT targets registered"
    EOT
  }

  depends_on = [aws_lb_target_group.kong_nlb]
}

# HTTPS Listener for ALB
# Listens on port 443 and forwards to Kong NLB target group
resource "aws_lb_listener" "cloudfront_https" {
  count = var.kong_nlb_dns_name != null && var.kong_nlb_security_group_id != null ? 1 : 0

  load_balancer_arn = aws_lb.cloudfront[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # Use default certificate for now (can be updated to use ACM certificate later)
  # For CloudFront VPC Origin, the ALB certificate is validated separately
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_nlb[0].arn
  }

  depends_on = [aws_lb.cloudfront, aws_lb_target_group.kong_nlb]
}

# HTTP Listener (forwards to Kong NLB)
# CloudFront handles TLS termination, so HTTP is sufficient for VPC Origin
resource "aws_lb_listener" "cloudfront_http" {
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

