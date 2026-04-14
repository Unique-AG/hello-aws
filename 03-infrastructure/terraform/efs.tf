#######################################
# EFS — Shared Storage for Docling Models
#######################################
#
# EFS provides ReadWriteMany (RWX) access for the ingestor pods,
# enabling horizontal scaling with KEDA while sharing the Docling
# model cache across replicas.
#
# Architecture:
#   - Single EFS file system with one access point (POSIX uid/gid 1000)
#   - Mount targets in each private subnet
#   - TLS in transit via efs-utils (mountOptions: [tls] in K8s PV)
#   - Elastic throughput to handle burst model reads on cold start
#######################################

resource "aws_efs_file_system" "docling_models" {
  encrypted        = true
  kms_key_id       = aws_kms_key.general.arn
  throughput_mode  = "elastic"
  performance_mode = "generalPurpose"

  tags = merge(module.naming.tags, {
    Name    = "efs-${module.naming.id}-docling-models"
    Purpose = "docling-models"
  })

  lifecycle {
    prevent_destroy = true
  }
}

#######################################
# Security Group — NFS access from VPC
#######################################

resource "aws_security_group" "efs" {
  name        = "${module.naming.id}-efs"
  description = "Security group for EFS mount targets"
  vpc_id      = aws_vpc.main.id

  tags = merge(module.naming.tags, {
    Name = "sg-${module.naming.id}-efs"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_vpc" {
  security_group_id = aws_security_group.efs.id
  description       = "Allow NFS from VPC primary CIDR"
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

#######################################
# Mount Targets — one per private subnet
#######################################

resource "aws_efs_mount_target" "docling_models" {
  count = length(aws_subnet.private)

  file_system_id  = aws_efs_file_system.docling_models.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# Access points are created dynamically by the EFS CSI driver
# via the efs-sc StorageClass (provisioningMode: efs-ap)
