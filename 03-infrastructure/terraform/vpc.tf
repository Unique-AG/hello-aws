# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    local.tags,
    {
      Name = "vpc-${module.naming.id}"
    }
  )
}

# Secondary CIDR for EKS pod networking (RFC 6598 range)
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = var.enable_secondary_cidr ? 1 : 0

  vpc_id     = aws_vpc.main.id
  cidr_block = "100.64.0.0/20"
}

# Restrict Default Security Group — deny all traffic
# Prevents accidental use of the VPC default security group
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # No ingress/egress rules = deny all
  tags = merge(local.tags, { Name = "sg-default-${module.naming.id}-DO-NOT-USE" })
}

# VPC Flow Logs — capture all traffic for audit and troubleshooting
resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs.arn
  max_aggregation_interval = 60
  tags                     = merge(local.tags, { Name = "flow-log-${module.naming.id}" })
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "${module.naming.log_group_prefix}/vpc-flow-logs"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn
  tags = merge(local.tags, {
    Name    = "log-${module.naming.id}-vpc-flow-logs"
    Purpose = "vpc-flow-logs"
  })
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${module.naming.id}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.tags, { Name = "${module.naming.id}-vpc-flow-logs" })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${module.naming.id}-vpc-flow-logs"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      }
    ]
  })
}

# DHCP Options for DNS Resolution
# Use AWS DNS (Amazon Route 53 Resolver) - AWS best practice
# AWS DNS automatically handles:
# - VPC endpoint private DNS resolution (resolves AWS service endpoints to VPC endpoint IPs)
# - Private hosted zones (Route 53)
# - External domain resolution (forwards to public DNS resolvers)
# No custom DNS servers needed - AWS DNS provides both internal and external resolution
resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "${var.aws_region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"] # AWS DNS resolver (VPC base IP + 2)

  tags = merge(
    local.tags,
    {
      Name = "dhcp-${module.naming.id}"
    }
  )
}

# Associate DHCP Options with VPC
resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}

# Internet Gateway
# Required for:
# - NAT Gateway (provides IPv4 internet access for private subnets)
# - EKS pods connecting to Microsoft Entra (HTTPS to login.microsoftonline.com)
# - ECR pull-through cache connecting to Azure Container Registry (HTTPS to uniqueapp.azurecr.io)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.tags,
    {
      Name = "igw-${module.naming.id}"
    }
  )
}

# Public Subnets (for NAT Gateway only)
# Note: EKS load balancers are internal and use private subnets
resource "aws_subnet" "public" {
  count = length(local.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, local.subnet_allocations.public.newbits, local.subnet_allocations.public.start + count.index)
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    local.tags,
    {
      Name                                        = "subnet-public-${module.naming.id}-${count.index + 1}"
      Type                                        = "public"
      "kubernetes.io/cluster/${module.naming.id}" = "shared"
    }
  )
}

# Private Subnets (for workloads: EKS, compute, AI, monitoring, etc.)
# Network segmentation achieved via Security Groups and NACLs, not separate subnets
resource "aws_subnet" "private" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_allocations.private.newbits, local.subnet_allocations.private.start + count.index)
  availability_zone = local.availability_zones[count.index]

  tags = merge(
    local.tags,
    {
      Name                                        = "subnet-private-${module.naming.id}-${count.index + 1}"
      Type                                        = "private"
      "kubernetes.io/role/internal-elb"           = "1" # For EKS internal load balancers
      "kubernetes.io/cluster/${module.naming.id}" = "shared"
    }
  )
}

# Isolated Subnets (for databases: RDS, ElastiCache)
# No internet access - maximum security for data stores
resource "aws_subnet" "isolated" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_allocations.isolated.newbits, local.subnet_allocations.isolated.start + count.index)
  availability_zone = local.availability_zones[count.index]

  tags = merge(
    local.tags,
    {
      Name    = "subnet-isolated-${module.naming.id}-${count.index + 1}"
      Type    = "isolated"
      Purpose = "database"
    }
  )
}

# NAT Gateway HA guard — warn if production uses single NAT
check "nat_gateway_ha" {
  assert {
    condition     = !(var.single_nat_gateway && var.environment == "prod")
    error_message = "Production environments should use multiple NAT Gateways for high availability. Set single_nat_gateway = false for prod."
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  domain = "vpc"

  tags = merge(
    local.tags,
    {
      Name = "eip-nat-${module.naming.id}-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
# Provides outbound IPv4 internet access for private subnets (EKS pods)
# Required for:
# - EKS pods connecting to Microsoft Entra (HTTPS)
# - ECR pull-through cache connecting to Azure Container Registry (HTTPS)
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.tags,
    {
      Name = "nat-${module.naming.id}-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Public Subnets
# Routes IPv4 traffic to Internet Gateway (required for NAT Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.tags,
    {
      Name = "rt-public-${module.naming.id}"
    }
  )
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Tables for Private Subnets (one per AZ, always created)
# NAT route is added separately so private subnets always have a route table
# and S3/other gateway endpoints are always associated
resource "aws_route_table" "private" {
  count = length(local.availability_zones)

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.tags,
    {
      Name = "rt-private-${module.naming.id}-${count.index + 1}"
    }
  )
}

# NAT Gateway route for private subnets (conditional on NAT being enabled)
resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(local.availability_zones) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
}

# Route Table Associations for Private Subnets (always associated)
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Route Tables for Isolated Subnets (no internet access - no NAT Gateway route)
resource "aws_route_table" "isolated" {
  count = length(local.availability_zones)

  vpc_id = aws_vpc.main.id

  # No default route - isolated from internet
  # Only VPC-internal routing

  tags = merge(
    local.tags,
    {
      Name = "rt-isolated-${module.naming.id}-${count.index + 1}"
    }
  )
}

# Route Table Associations for Isolated Subnets
resource "aws_route_table_association" "isolated" {
  count = length(aws_subnet.isolated)

  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated[count.index].id
}

