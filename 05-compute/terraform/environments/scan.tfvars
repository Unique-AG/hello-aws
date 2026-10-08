# Scanning only — never used for a deploy.
# Every enable_* flag, so a component cannot escape the gate by being
# disabled in the environment CI reads. Gates named otherwise (use_oidc,
# connectivity_account_id, ...) are not covered yet.

enable_podvm_image_import = true
