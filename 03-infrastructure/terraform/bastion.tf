# IAM Role for EC2 instances to use Session Manager
resource "aws_iam_role" "ssm_instance" {
  name = "${module.naming.id}-ssm-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${module.naming.id}-ssm-instance-role"
  }
}

# Attach AWS managed policy for Session Manager
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ssm_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Policy to allow management server to access EKS cluster
# Restricted to specific cluster ARNs instead of wildcard for security
resource "aws_iam_role_policy" "ssm_instance_eks_access" {
  name = "${module.naming.id}-ssm-instance-eks-access"
  role = aws_iam_role.ssm_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = [
          "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${module.naming.id}-*"
        ]
      }
    ]
  })
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "ssm_instance" {
  name = "${module.naming.id}-ssm-instance-profile"
  role = aws_iam_role.ssm_instance.name
}

# Security Group for Management Server
resource "aws_security_group" "management_server" {
  name        = "${module.naming.id}-management-server"
  description = "Security group for management/jump server"
  vpc_id      = aws_vpc.main.id

  # Note: IMDS (Instance Metadata Service) is link-local (169.254.169.254)
  # Security groups do NOT control IMDS access - it's handled at the hypervisor level
  # IMDSv2 is enforced via instance metadata_options (http_tokens = "required")
  # If IMDS doesn't work, ensure the instance has been rebooted after metadata options were set

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${module.naming.id}-management-server-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "management_server_ssh" {
  for_each = toset(var.secondary_cidr_enabled ? [aws_vpc.main.cidr_block, local.secondary_cidr] : [aws_vpc.main.cidr_block])

  security_group_id = aws_security_group.management_server.id
  description       = "SSH from VPC (Session Manager port forwarding)"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "management_server_to_vpc" {
  for_each = toset(var.secondary_cidr_enabled ? [aws_vpc.main.cidr_block, local.secondary_cidr] : [aws_vpc.main.cidr_block])

  security_group_id = aws_security_group.management_server.id
  description       = "Allow all outbound to VPC (${each.value})"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Management Server
resource "aws_instance" "management_server" {
  count = var.management_server_enabled ? 1 : 0

  ami           = var.management_server_ami != "" ? var.management_server_ami : data.aws_ami.amazon_linux_2023.id
  instance_type = var.management_server_instance_type
  subnet_id     = var.management_server_public_access ? aws_subnet.public[0].id : aws_subnet.private[0].id

  vpc_security_group_ids = [aws_security_group.management_server.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance.name

  # User data for initial setup
  # Reads from user-data/management-server.sh and substitutes the hostname variable
  user_data = base64encode(
    replace(
      file("${path.module}/user-data/management-server.sh"),
      "$${hostname}",
      "${module.naming.id}-management"
    )
  )

  # Enable detailed monitoring
  monitoring = var.management_server_monitoring

  # Enforce IMDSv2 (Instance Metadata Service Version 2)
  # This prevents SSRF attacks and enforces secure metadata access
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Enable EBS optimization for better performance
  ebs_optimized = true

  # Root volume configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = var.management_server_disk_size
    encrypted   = true
    kms_key_id  = aws_kms_key.general.arn

    tags = {
      Name = "${module.naming.id}-management-server-root"
    }
  }

  # Associate public IP only if public access is enabled
  associate_public_ip_address = var.management_server_public_access

  tags = {
    Name = "${module.naming.id}-management-server"
  }
}

# Elastic IP for Management Server (if public access enabled)
resource "aws_eip" "management_server" {
  count = var.management_server_enabled && var.management_server_public_access ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.management_server[0].id

  tags = {
    Name = "${module.naming.id}-management-server-eip"
  }
}

