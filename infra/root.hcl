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

  # JFrog Cloud trial — state backend migrated from S3 for testing. remote (not http) — JFrog's TFC-compatible API is what actually implements real locking; confirmed live via `terraform login`, which succeeded with a genuine OAuth flow against this instance. The http backend's raw content API worked for read/write but proved (via a real concurrent-PUT test) to have no actual locking, hence this switch.
  jfrog_hostname = "trialc6mgth.jfrog.io"
  repo_name      = "terraform-state-local"
}

# dev/qa/prod all destroyed clean on S3 before this switch, so this starts genuinely empty on JFrog — no migration needed, see infra-envs/dev's real destroy + confirmed-empty state list before this changed.
#
# Hand-written via generate, not remote_state — Terragrunt's remote_state.config only produces flat key = value attributes, but the remote backend's workspaces has to be a real nested block (workspaces { name = "..." }), confirmed by a real "Unsupported argument" error when remote_state generated workspaces = { ... } instead. organization is the repository name in JFrog's TFC-compatible mapping, not a literal org. Auth comes from `terraform login`'s locally-stored OAuth token, not username/password — nothing credential-shaped belongs in this file at all for the remote backend.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "remote" {
    hostname     = "${local.jfrog_hostname}"
    organization = "${local.repo_name}"

    workspaces {
      name = "thor-${local.environment}"
    }
  }
}
EOF
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

# Publishes every Lambda function's real code before plan/apply/destroy, so archive_file has something real to zip — Terraform can't compile C#. destroy still fully evaluates the resource graph (including archive_file) to know what to tear down, so it needs publish/ to exist too, same as plan/apply. get_repo_root() keeps this absolute, since Terragrunt only copies infra/src into its working directory.
terraform {
  before_hook "publish_lambda_functions" {
    commands     = ["plan", "apply", "destroy"]
    execute      = ["${get_repo_root()}/scripts/publish-lambda-functions.sh"]
    run_on_error = false
  }
}
