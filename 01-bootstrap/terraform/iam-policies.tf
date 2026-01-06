# IAM policy for GitHub Actions to manage Terraform state
resource "aws_iam_role_policy" "github_actions_terraform" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  name = "${module.naming.iam_role_prefix}-terraform-state-access"
  role = aws_iam_role.github_actions[0].id

  policy = templatefile("${path.module}/policies/github-actions-terraform-state.json", {
    s3_bucket_arn = aws_s3_bucket.terraform_state.arn
    kms_key_arn   = var.enable_server_side_encryption ? aws_kms_key.terraform_state[0].arn : "*"
  })
}

