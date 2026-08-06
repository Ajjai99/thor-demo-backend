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

# Bootstrap placeholder — lets this resource exist before any real authorizer code is built/deployed. A real deploy pipeline overwrites the function code directly (aws lambda update-function-code); filename/source_code_hash are ignored below so Terraform never reverts that.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = "Bootstrap placeholder — not a real authorizer implementation. Replace via a real deploy pipeline."
    filename = "PLACEHOLDER"
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "authorizer" {
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Scoped to this environment's Aurora cluster/secret only — ExecuteStatement is the RDS Data API call the authorizer uses to look up a hashed key; GetSecretValue is required alongside it since Data API authenticates against the cluster via this secret.
data "aws_iam_policy_document" "aurora_data_api" {
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
  role   = aws_iam_role.authorizer.id
  policy = data.aws_iam_policy_document.aurora_data_api.json
}

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_lambda_function" "authorizer" {
  function_name = local.name_prefix
  role          = aws_iam_role.authorizer.arn
  runtime       = "dotnet10"
  # Matches backend/functions/Thor.Authorizer/src (assembly Thor.Authorizer, namespace Thor.Authorizer, class Function) — kept in sync with ignore_changes below only until a real deploy pipeline takes over.
  handler     = "Thor.Authorizer::Thor.Authorizer.Function::FunctionHandler"
  timeout     = 5
  memory_size = 256

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ARN   = var.aurora_cluster_arn
      AURORA_SECRET_ARN    = var.aurora_secret_arn
      AURORA_DATABASE_NAME = var.aurora_database_name
    }
  }

  # A real deploy pipeline owns pushing actual authorizer code/handler — this resource just needs to exist for API Gateway to attach to.
  lifecycle {
    ignore_changes = [filename, source_code_hash, handler]
  }

  depends_on = [aws_cloudwatch_log_group.authorizer, aws_iam_role_policy_attachment.logs, aws_iam_role_policy.aurora_data_api]

  tags = var.tags
}
