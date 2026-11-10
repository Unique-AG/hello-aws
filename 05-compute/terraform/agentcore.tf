#######################################
# Bedrock AgentCore
#######################################
#
# AgentCore Web Search is called through the InvokeWebSearch API on the AgentCore
# data plane. There is nothing to create: the tool is an AWS-owned resource, so
# enabling it is a grant plus (optionally) the VPC endpoint in 03-infrastructure.
#######################################

data "aws_iam_policy_document" "agentcore_web_search" {
  statement {
    sid     = "AllowInvokeWebSearch"
    effect  = "Allow"
    actions = ["bedrock-agentcore:InvokeWebSearch"]
    # The account field is the literal "aws": AWS owns the managed tool, so this
    # is not the deployment's account id and must not be templated as one.
    resources = ["arn:aws:bedrock-agentcore:${var.aws_region}:aws:tool/web-search.v1"]
  }
}

# Separate from the role's bedrock-s3-secrets-access policy so web search can be
# turned off without rewriting the model and storage grants.
resource "aws_iam_role_policy" "assistants_core_agentcore_web_search" {
  count = var.enable_agentcore_web_search ? 1 : 0

  name   = "agentcore-web-search"
  role   = aws_iam_role.assistants_core.id
  policy = data.aws_iam_policy_document.agentcore_web_search.json
}
