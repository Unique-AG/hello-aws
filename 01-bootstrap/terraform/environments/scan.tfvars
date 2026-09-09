# Scanning only — never used for a deploy.
# Every enable_* flag, so a conditional resource cannot escape the gate
# by being disabled in the environment CI reads.

enable_public_access_block    = true
enable_server_side_encryption = true
enable_versioning             = true
