#######################################
# Bedrock AgentCore
#######################################
# Web Search is an AWS-owned managed tool, so there is nothing to create: it is
# a grant, plus the VPC endpoint in 03-infrastructure.

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

#######################################
# AgentCore Gateway (Web Search over MCP)
#######################################
# Exposes web search as an MCP tool, so agents find it with tools/list rather
# than calling InvokeWebSearch themselves.

data "aws_iam_policy_document" "agentcore_gateway_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    # Confused-deputy protection: the service may only assume this role on
    # behalf of this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "agentcore_gateway" {
  count = var.enable_agentcore_gateway ? 1 : 0

  name               = "${module.naming.id}-agentcore-gateway"
  assume_role_policy = data.aws_iam_policy_document.agentcore_gateway_assume.json

  tags = {
    Name = "${module.naming.id}-agentcore-gateway"
  }
}

data "aws_iam_policy_document" "agentcore_gateway" {
  statement {
    sid       = "InvokeGateway"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = ["arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:gateway/*"]
  }

  statement {
    sid       = "InvokeWebSearch"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeWebSearch"]
    resources = ["arn:aws:bedrock-agentcore:${var.aws_region}:aws:tool/web-search.v1"]
  }
}

resource "aws_iam_role_policy" "agentcore_gateway" {
  count = var.enable_agentcore_gateway ? 1 : 0

  name   = "agentcore-gateway-web-search"
  role   = aws_iam_role.agentcore_gateway[0].id
  policy = data.aws_iam_policy_document.agentcore_gateway.json
}

resource "aws_bedrockagentcore_gateway" "web_search" {
  count = var.enable_agentcore_gateway ? 1 : 0

  name     = "${module.naming.id}-web-search"
  role_arn = aws_iam_role.agentcore_gateway[0].arn

  # Callers authenticate with SigV4, so in-cluster agents reach the gateway with
  # their Pod Identity credentials and no second identity provider is needed.
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"

  tags = {
    Name = "${module.naming.id}-web-search"
  }
}

# Cloud Control rather than aws_bedrockagentcore_gateway_target: that resource
# carries every target type except "connector", which is the one web search needs.
resource "aws_cloudcontrolapi_resource" "web_search_target" {
  count = var.enable_agentcore_gateway ? 1 : 0

  type_name = "AWS::BedrockAgentCore::GatewayTarget"

  desired_state = jsonencode({
    GatewayIdentifier = aws_bedrockagentcore_gateway.web_search[0].gateway_id
    Name              = "web-search-tool"
    TargetConfiguration = {
      Mcp = {
        Connector = {
          Source         = { ConnectorId = "web-search" }
          Configurations = [{ Name = "WebSearch", ParameterValues = {} }]
        }
      }
    }
    CredentialProviderConfigurations = [{ CredentialProviderType = "GATEWAY_IAM_ROLE" }]
  })
}

# The gateway authorizes callers with IAM, so the agent needs its own grant; the
# gateway's service role is what reaches web search behind it.
data "aws_iam_policy_document" "assistants_core_agentcore_gateway" {
  count = var.enable_agentcore_gateway ? 1 : 0

  statement {
    sid       = "InvokeWebSearchGateway"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.web_search[0].gateway_arn]
  }
}

resource "aws_iam_role_policy" "assistants_core_agentcore_gateway" {
  count = var.enable_agentcore_gateway ? 1 : 0

  name   = "agentcore-gateway-invoke"
  role   = aws_iam_role.assistants_core.id
  policy = data.aws_iam_policy_document.assistants_core_agentcore_gateway[0].json
}
