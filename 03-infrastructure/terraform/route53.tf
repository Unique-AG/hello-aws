# Associate this VPC with the Route 53 Private Hosted Zone from landing zone
# Authorization must be done in landing zone account first
resource "aws_route53_zone_association" "vpc" {
  count = var.route53_private_zone_domain != null && var.route53_private_zone_id != null ? 1 : 0

  zone_id    = var.route53_private_zone_id
  vpc_id     = aws_vpc.main.id
  vpc_region = var.aws_region
}
