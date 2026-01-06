terraform {
  # Backend configuration is loaded from backend-config.hcl
  # When running Terraform in GitHub Actions, the provider will detect the ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN environment variables set by the GitHub Actions runtime
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/security-tokens#oidc-token
  backend "s3" {
    # Backend configuration is provided via environments/{env}/backend-config.hcl
    # The S3 bucket stores state files from all layers, each in its own path
    # Example for bootstrap layer:
    # bucket         = "s3-acme-dogfood-x-euc2-tfstate"
    # key            = "bootstrap/terraform.tfstate"  # Layer-specific path
    # region         = "eu-central-2"
    # encrypt        = true
    # kms_key_id     = "alias/kms-acme-dogfood-sbx-euc2-tfstate"
    # use_lockfile   = true
    #
    # Uses the same S3 bucket and KMS key across all layers
    # Native S3 locking (use_lockfile) replaces DynamoDB table
  }
}

