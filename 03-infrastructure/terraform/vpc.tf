#######################################
# VPC and Networking
#######################################
#
# Creates a VPC following AWS best practices:
# - Public subnets: For NAT Gateway (one per AZ for high availability)
#   - EKS load balancers are internal and use private subnets
# - Private subnets: For workloads (EKS, compute, AI, monitoring, internal load balancers)
#   - Has outbound internet access via NAT Gateway
#   - Use security groups and NACLs for segmentation
# - Isolated subnets: For databases (RDS, ElastiCache)
#   - No internet access (no NAT Gateway route)
#   - Maximum security for data stores
#
# Network segmentation is achieved through:
# - Security Groups (instance-level firewall)
# - Network ACLs (subnet-level firewall)
# - VPC Endpoints (for AWS services)
# - Not through separate subnets per service type
#######################################

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

# DHCP Options for DNS Resolution
# Use AWS DNS (Amazon Route 53 Resolver) - AWS best practice
# AWS DNS automatically handles:
# - VPC endpoint private DNS resolution (resolves AWS service endpoints to VPC endpoint IPs)
# - Private hosted zones (Route 53)
# - External domain resolution (forwards to public DNS resolvers)
# No custom DNS servers needed - AWS DNS provides both internal and external resolution
resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "eu-central-2.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]  # AWS DNS resolver (VPC base IP + 2)

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
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, local.subnet_allocations.public.start + count.index)
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.tags,
    {
      Name = "subnet-public-${module.naming.id}-${count.index + 1}"
      Type = "public"
    }
  )
}

# Private Subnets (for workloads: EKS, compute, AI, monitoring, etc.)
# Network segmentation achieved via Security Groups and NACLs, not separate subnets
resource "aws_subnet" "private" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, local.subnet_allocations.private.start + count.index)
  availability_zone = local.availability_zones[count.index]

  tags = merge(
    local.tags,
    {
      Name                              = "subnet-private-${module.naming.id}-${count.index + 1}"
      Type                              = "private"
      "kubernetes.io/role/internal-elb" = "1" # For EKS internal load balancers
    }
  )
}

# Isolated Subnets (for databases: RDS, ElastiCache)
# No internet access - maximum security for data stores
resource "aws_subnet" "isolated" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, local.subnet_allocations.isolated.start + count.index)
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

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? length(local.availability_zones) : 0

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
  count = var.enable_nat_gateway ? length(local.availability_zones) : 0

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

# Route Tables for Private Subnets (one per AZ)
resource "aws_route_table" "private" {
  count = var.enable_nat_gateway ? length(local.availability_zones) : 0

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    local.tags,
    {
      Name = "rt-private-${module.naming.id}-${count.index + 1}"
    }
  )
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "private" {
  count = var.enable_nat_gateway ? length(aws_subnet.private) : 0

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

