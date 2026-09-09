# Scanning only — never applied.
#
# Defines the posture the gate checks: every optional component switched on,
# and every safety knob at its production value. Layered after the environment
# config so it wins, which is how a relaxation an environment makes on purpose
# still gets scanned as if production.

# Components
enable_public_access_block    = true
enable_server_side_encryption = true
enable_versioning             = true

# The CI deploy role only exists when both of these are set.
use_oidc          = true
github_repository = "Unique-AG/hello-aws"

# Safety knobs
cloudwatch_log_retention_days = 365
