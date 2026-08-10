locals {
  environment = basename(get_original_terragrunt_dir())

  account_map = {
    dev = {
      account_id = "877969058937" # Account A, shared with qa — provide aws-account-id
      aws_region = "us-east-1"
    }
    qa = {
      account_id = "877969058937" # Account A, shared with dev — provide aws-account-id
      aws_region = "us-east-1"
    }
    prod = {
      account_id = "ACCOUNT-ID" # Account B, isolated from dev/qa — provide aws-account-id
      aws_region = "us-east-1"
    }
  }

  account = local.account_map[local.environment]
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "thor-terraform-state-${local.account.account_id}"
    key          = "thor-${local.environment}/terraform.tfstate"
    region       = local.account.aws_region
    use_lockfile = true
    encrypt      = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "${local.account.aws_region}"


  default_tags {
    tags = {
      Project     = "thor-platform"
      Environment = "${local.environment}"
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}

inputs = {
  environment = local.environment
}

# Publishes every Lambda function's real code before plan/apply, so archive_file has something real to zip — Terraform can't compile C#. get_repo_root() keeps this absolute, since Terragrunt only copies infra/src into its working directory.
terraform {
  before_hook "publish_lambda_functions" {
    commands     = ["plan", "apply"]
    execute      = ["${get_repo_root()}/scripts/publish-lambda-functions.sh"]
    run_on_error = false
  }
}
