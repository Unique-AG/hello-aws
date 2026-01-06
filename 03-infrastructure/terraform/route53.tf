#######################################
# Route 53 Private Hosted Zone VPC Association
#######################################
#
# Associates this VPC with the Route 53 Private Hosted Zone shared from the landing zone.
# This enables DNS resolution for this VPC in the shared zone.
#
# Note: Authorization must be done in landing zone account first.
# The authorization is created in aws-organizations/04-infrastructure/terraform/route53.tf
#
# Architecture Decision:
# - VPC association is infrastructure-level configuration, not compute-specific
# - DNS records for workload-specific resources (EKS, RDS, ElastiCache) are created
#   in their respective layers (compute, data-and-ai)
# - This maintains separation of concerns: infrastructure manages VPC-level DNS,
#   workload layers manage their own resource DNS records
#######################################

# Associate this VPC with the Route 53 Private Hosted Zone from landing zone
# This enables DNS resolution for this VPC in the shared zone
# Note: Authorization must be done in landing zone account first
# We use the zone ID directly since the zone isn't visible until after association
resource "aws_route53_zone_association" "vpc" {
  count = var.route53_private_zone_domain != null && var.route53_private_zone_id != null ? 1 : 0

  zone_id    = var.route53_private_zone_id
  vpc_id     = aws_vpc.main.id
  vpc_region = var.aws_region

  # Note: This association requires authorization from the landing zone account
  # The authorization is created in aws-organizations/04-infrastructure/terraform/route53.tf
}

