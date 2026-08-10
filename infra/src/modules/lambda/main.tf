terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

locals {
  name_prefix = "thor-${var.environment}-api-key-authorizer"
}

# source_dir is an absolute path (terragrunt.hcl builds it with get_repo_root(), not path.module) since Terragrunt only copies infra/src into its working directory — backend/functions/Thor.Authorizer isn't reachable via a relative path. output_path is derived from that same absolute path for the same reason: a path under path.module would only exist in whichever ephemeral cache copy ran `plan`, not necessarily the one `apply` runs from. Requires `dotnet publish` into authorizer_source_dir before terragrunt runs — Terraform zips, it doesn't compile.
data "archive_file" "thor-authorizer-archive-file" {
  type        = "zip"
  source_dir  = var.authorizer_source_dir
  output_path = "${var.authorizer_source_dir}/../thor-authorizer-build.zip"
}

data "aws_iam_policy_document" "thor-lambda-authorizer-assume-policy-document" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "thor-lambda-authorizer-role" {
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.thor-lambda-authorizer-assume-policy-document.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "thor-lambda-authorizer-policy-attachment" {
  role       = aws_iam_role.thor-lambda-authorizer-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Scoped to this environment's Aurora cluster/secret only — ExecuteStatement is the RDS Data API call the authorizer uses to look up a hashed key; GetSecretValue is required alongside it since Data API authenticates against the cluster via this secret.
data "aws_iam_policy_document" "aurora-data-api-policy-document" {
  statement {
    actions   = ["rds-data:ExecuteStatement"]
    resources = [var.aurora_cluster_arn]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.aurora_secret_arn]
  }
}

resource "aws_iam_role_policy" "aurora_data_api" {
  name   = "aurora-data-api-access"
  role   = aws_iam_role.thor-lambda-authorizer-role.id
  policy = data.aws_iam_policy_document.aurora-data-api-policy-document.json
}

resource "aws_cloudwatch_log_group" "thor-lambda-authorizer-logs" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_lambda_function" "thor-authorizer-lambda" {
  function_name = local.name_prefix
  role          = aws_iam_role.thor-lambda-authorizer-role.arn
  runtime = var.runtime
  # Matches backend/functions/Thor.Authorizer/src (assembly Thor.Authorizer, namespace Thor.Authorizer, class Function) — kept in sync with ignore_changes below only until a real deploy pipeline takes over.
  handler     = "Thor.Authorizer::Thor.Authorizer.Function::FunctionHandler"
  timeout     = var.timeout
  memory_size = var.memory_size

  filename         = data.archive_file.thor-authorizer-archive-file.output_path
  source_code_hash = data.archive_file.thor-authorizer-archive-file.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ARN   = var.aurora_cluster_arn
      AURORA_SECRET_ARN    = var.aurora_secret_arn
      AURORA_DATABASE_NAME = var.aurora_database_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.thor-lambda-authorizer-logs, aws_iam_role_policy_attachment.thor-lambda-authorizer-policy-attachment, aws_iam_role_policy.aurora_data_api]

  tags = var.tags
}
