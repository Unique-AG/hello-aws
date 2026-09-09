# Scanning only — never used for a deploy.
# Forces every conditional resource into scope so a misconfiguration
# cannot merge green just because an environment leaves its flag off.

enable_aurora_endpoint      = true
enable_bedrock_logging      = true
enable_elasticache_endpoint = true
enable_managed_grafana      = true
enable_managed_prometheus   = true
enable_s3_vpc_only_policy   = true
