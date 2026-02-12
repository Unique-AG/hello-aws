terraform {
  # GitHub Actions OIDC: provider auto-detects ACTIONS_ID_TOKEN_REQUEST_* env vars
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/security-tokens#oidc-token
  backend "s3" {
    # Provided via environments/{env}/backend-config.hcl
    # All layers share one S3 bucket, each with its own key path
    # Native S3 locking (use_lockfile) replaces DynamoDB
  }
}
