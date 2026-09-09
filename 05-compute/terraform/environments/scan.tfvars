# Scanning only — never used for a deploy.
# Every enable_* flag, so a conditional resource cannot escape the gate
# by being disabled in the environment CI reads.

enable_podvm_image_import = true
