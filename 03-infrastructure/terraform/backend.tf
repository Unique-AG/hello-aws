terraform {
  # Backend configuration is loaded from backend-config.hcl
  # When running Terraform in GitHub Actions, the provider will detect the ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN environment variables set by the GitHub Actions runtime
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/security-tokens#oidc-token
  backend "s3" {
    # Backend configuration is provided via environments/{env}/backend-config.hcl
    # The S3 bucket stores state files from all layers, each in its own path
    # Example for infrastructure layer:
    # bucket         = "s3-uq-acme-p-euc2-123456789012-terraform-state"
    # key            = "infrastructure/terraform.tfstate"  # Layer-specific path
    # region         = "eu-central-2"
    # dynamodb_table = "dynamodb-uq-acme-prod-euc2-terraform-state-lock"
    # encrypt        = true
    # kms_key_id     = "alias/kms-uq-acme-prod-euc2-terraform-state"
    #
    # Uses the same S3 bucket, DynamoDB table, and KMS key as bootstrap layer
  }
}

