# Scanning only — never applied. See 01-bootstrap/terraform/environments/scan.tfvars.

# Components
enable_aurora_endpoint      = true
enable_bedrock_logging      = true
enable_elasticache_endpoint = true
enable_managed_grafana      = true
enable_managed_prometheus   = true
enable_s3_vpc_only_policy   = true

# Safety knobs. Capacity and cost knobs (instance counts, node counts, AZ
# count, budget) are deliberately not pinned: they change how many resources
# exist rather than whether one is configured safely.
aurora_deletion_protection             = true
elasticache_automatic_failover_enabled = true
elasticache_multi_az_enabled           = true
elasticache_snapshot_retention_limit   = 5
secrets_recovery_window_days           = 30

# Not a component: a supplied master password is the relaxation, a generated
# one is the default. Left off so the scan checks the default path.
set_aurora_master_password = false
