#######################################
# Secrets Manager
#######################################
#
# AWS Secrets Manager for storing and managing secrets.
# Uses customer-managed KMS key for encryption.
#
# Note: Specific secrets are created in their respective layers.
# This file sets up the service configuration.
#######################################

# Note: Secrets Manager doesn't require a separate resource to be "enabled"
# The service is available by default. We just need to ensure:
# 1. VPC endpoint is configured (already done in vpc-endpoints.tf)
# 2. KMS key is available (created in kms.tf)
# 3. IAM policies allow access (configured in respective layers)

# Output the KMS key ARN for use in other layers
# This allows other layers to reference the Secrets Manager KMS key
# when creating secrets

