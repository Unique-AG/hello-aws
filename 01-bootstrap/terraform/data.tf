data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Resolve assumed-role session ARNs back to their underlying IAM role so the
# terraform_state bucket policy doesn't drift every invocation as the session
# token rotates (each terraform run gets a new aws-go-sdk-XXX session ARN).
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}
