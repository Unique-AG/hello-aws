locals {
  # Secondary CIDR for EKS pod networking (RFC 6598 range)
  secondary_cidr = "100.64.0.0/20"

  # Terraform state bucket name (computed from naming module, same as bootstrap layer)
  # Format: s3-{id_short}-tfstate
  # This matches the bootstrap layer's bucket name generation
  terraform_state_bucket = "${module.naming.s3_bucket_prefix}-tfstate"

  # Availability zones (configurable per environment)
  availability_zones = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)

  # Number of NAT gateways (single or per-AZ)
  nat_gateway_count = var.single_nat_gateway ? 1 : length(local.availability_zones)

  # VPC prefix length — used to compute cidrsubnet newbits dynamically
  # so subnet sizes stay fixed regardless of VPC CIDR size
  vpc_prefix_length = tonumber(split("/", var.vpc_cidr)[1])

  # Subnet CIDR allocation — right-sized per subnet role
  # newbits computed dynamically: desired_prefix - vpc_prefix_length
  # Start indexes are stable across VPC sizes (verified non-overlapping).
  #
  # | Subnet   | Size | start | Example (10.1.0.0/19, 3 AZs)         |
  # |----------|------|-------|---------------------------------------|
  # | Private  | /22  | 0     | 10.1.0.0, 10.1.4.0, 10.1.8.0        |
  # | Public   | /28  | 192   | 10.1.12.0, 10.1.12.16, 10.1.12.32   |
  # | Isolated | /26  | 64    | 10.1.16.0, 10.1.16.64, 10.1.16.128  |
  # | Runners  | /26  | 80    | 10.1.20.0, 10.1.20.64, 10.1.20.128  |
  subnet_allocations = {
    public   = { newbits = 28 - local.vpc_prefix_length, start = 192 } # /28 — NAT GW, LBs (16 IPs)
    private  = { newbits = 22 - local.vpc_prefix_length, start = 0 }   # /22 — EKS nodes, compute (1024 IPs)
    isolated = { newbits = 26 - local.vpc_prefix_length, start = 64 }  # /26 — RDS, ElastiCache (64 IPs)
    runners  = { newbits = 26 - local.vpc_prefix_length, start = 80 }  # /26 — GitHub runners (64 IPs)
  }

  tags = module.naming.tags
}

