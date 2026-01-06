#######################################
# Transit Gateway VPC Attachment
#######################################
#
# Attaches the EKS VPC to the Transit Gateway from the connectivity layer.
# This enables hub-and-spoke network connectivity between:
# - Infrastructure VPC (landing zone)
# - EKS VPC (this account)
# - Future: On-premises networks via Direct Connect
#
# The Transit Gateway must be shared via AWS RAM from the connectivity account.
# Once shared, this attachment will be automatically accepted because the
# Transit Gateway has auto_accept_shared_attachments = "enable".
#
# Note: The Transit Gateway ID is provided as a variable from the connectivity layer.
#######################################

# Transit Gateway VPC Attachment for EKS VPC
resource "aws_ec2_transit_gateway_vpc_attachment" "eks" {
  count = var.transit_gateway_id != null ? 1 : 0

  subnet_ids         = local.infrastructure.private_subnet_ids
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = local.infrastructure.vpc_id

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = merge(
    local.tags,
    {
      Name = "${module.naming.id}-transit-gateway-attachment"
    }
  )
}

