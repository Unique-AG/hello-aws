# Scanning only — never used for a deploy.
# Every enable_* flag, so a component cannot escape the gate by being
# disabled in the environment CI reads. Gates named otherwise (use_oidc,
# connectivity_account_id, ...) are not covered yet.

enable_aurora_endpoint      = true
enable_bedrock_logging      = true
enable_elasticache_endpoint = true
enable_managed_grafana      = true
enable_managed_prometheus   = true
enable_s3_vpc_only_policy   = true
