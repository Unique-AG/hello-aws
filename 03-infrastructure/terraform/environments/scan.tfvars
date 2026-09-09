# Scanning only — never used for a deploy.
# Forces every conditional resource into scope so a misconfiguration
# cannot merge green just because an environment leaves its flag off.

enable_bedrock_endpoint          = true
enable_cloudwatch_endpoints      = true
enable_connectivity_account_role = true
enable_dns_hostnames             = true
enable_dns_support               = true
enable_ec2_endpoint              = true
enable_ecr_endpoints             = true
enable_eks_auth_endpoint         = true
enable_eks_endpoint              = true
enable_github_runners            = true
enable_kms_endpoint              = true
enable_managed_prometheus        = true
enable_management_server         = true
enable_nat_gateway               = true
enable_prometheus_endpoint       = true
enable_s3_gateway_endpoint       = true
enable_secondary_cidr            = true
enable_secrets_manager_endpoint  = true
enable_ssm_endpoints             = true
enable_sts_endpoint              = true
