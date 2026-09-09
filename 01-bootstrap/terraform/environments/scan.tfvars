# Scanning only — never used for a deploy.
# Forces every conditional resource into scope so a misconfiguration
# cannot merge green just because an environment leaves its flag off.

enable_public_access_block    = true
enable_server_side_encryption = true
enable_versioning             = true
