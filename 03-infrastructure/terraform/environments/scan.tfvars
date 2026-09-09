# Scanning only — never applied. See 01-bootstrap/terraform/environments/scan.tfvars.

# Components — VPC endpoints
enable_bedrock_endpoint         = true
enable_cloudwatch_endpoints     = true
enable_ec2_endpoint             = true
enable_ecr_endpoints            = true
enable_eks_auth_endpoint        = true
enable_eks_endpoint             = true
enable_kms_endpoint             = true
enable_prometheus_endpoint      = true
enable_s3_gateway_endpoint      = true
enable_secrets_manager_endpoint = true
enable_ssm_endpoints            = true
enable_sts_endpoint             = true

# Components — networking and ingress
enable_cloudfront_vpc_origin = true
enable_ingress_nlb           = true
enable_nat_gateway           = true
enable_secondary_cidr        = true

# Components — operational
enable_github_runners     = true
enable_managed_prometheus = true
enable_management_server  = true

# Cross-account role and peering only exist when their ids are set. Values are
# well-formed placeholders; nothing here is applied.
enable_connectivity_account_role = true
connectivity_account_id          = "111122223333"
transit_gateway_id               = "tgw-0123456789abcdef0"
route53_private_zone_id          = "Z0123456789ABCDEFGHIJ"
route53_private_zone_domain      = "example.internal"
internal_alb_certificate_domain  = "example.internal"
alert_email_endpoints            = ["alerts@example.com"]

# Safety knobs — production values, so a relaxation an environment makes on
# purpose is still scanned as if production.
alb_deletion_protection       = true
management_server_monitoring  = true
cloudwatch_log_retention_days = 365

# Not components: a public bastion and a shared single NAT are relaxations, so
# the scan checks the hardened path.
management_server_public_access = false
single_nat_gateway              = false
