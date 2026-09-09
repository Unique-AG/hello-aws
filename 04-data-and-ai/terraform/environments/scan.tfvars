# Scanning only — never applied. See 01-bootstrap/terraform/environments/scan.tfvars.

# Components
enable_aurora_endpoint      = true
enable_bedrock_logging      = true
enable_elasticache_endpoint = true
enable_managed_grafana      = true
enable_managed_prometheus   = true
enable_s3_vpc_only_policy   = true

# Safety knobs
aurora_deletion_protection = true

# Not a component: a supplied master password is the relaxation, a generated
# one is the default. Left off so the scan checks the default path.
set_aurora_master_password = false
