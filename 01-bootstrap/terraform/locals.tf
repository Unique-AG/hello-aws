locals {
  s3_bucket_name           = "${module.naming.s3_bucket_prefix}-tfstate"
  kms_key_alias            = "alias/kms-${module.naming.id}-tfstate"
  layer_name               = "bootstrap"
  github_actions_role_name = "${module.naming.iam_role_prefix}-github-actions"
  tags                     = module.naming.tags
}
