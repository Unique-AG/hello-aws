# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, product, product_moniker, semantic_version)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# Secrets Configuration (immediate deletion for fast teardown)
secrets_recovery_window_days = 0

# Aurora Configuration (sandbox-specific)
aurora_instance_class      = "db.t4g.medium"
aurora_instance_count      = 1
aurora_deletion_protection = false
aurora_skip_final_snapshot = true

# ElastiCache Configuration (sandbox-specific)
elasticache_node_type                  = "cache.t3.micro"
elasticache_num_cache_nodes            = 1
elasticache_automatic_failover_enabled = false
elasticache_multi_az_enabled           = false
elasticache_snapshot_retention_limit   = 1

# Disable Grafana (not available in eu-central-2)
enable_managed_grafana = false

# VPC Endpoints
enable_aurora_endpoint      = true
enable_elasticache_endpoint = true
