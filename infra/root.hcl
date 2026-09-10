locals {
  environment = basename(get_original_terragrunt_dir())

  # aws_region is where this stack's regional resources actually live. state_region is where that
  # account's Terraform state bucket already exists, which is not the same thing and must not be
  # derived from aws_region — see the remote_state block below.
  account_map = {
    dev = {
      account_id   = "853973692277" # Account A, shared with qa — provide aws-account-id
      aws_region   = "us-west-2"
      state_region = "us-east-1"
    }
    qa = {
      account_id   = "853973692277" # Account A, shared with dev — provide aws-account-id
      aws_region   = "us-west-2"
      state_region = "us-east-1"
    }
    prod = {
      account_id   = "ACCOUNT-ID" # Account B, isolated from dev/qa — provide aws-account-id
      aws_region   = "us-west-2"
      state_region = "us-east-1"
    }
  }

  account = local.account_map[local.environment]

  # Not a preference — AWS fixes this. CloudFront reads its certificates only from us-east-1, and
  # CLOUDFRONT-scoped WAFv2 web ACLs are only creatable through the us-east-1 endpoint (any other
  # region rejects the scope outright with WAFInvalidParameterException). Passed to the root module
  # as var.global_region, which pins exactly those resources while everything else stays in
  # local.account.aws_region. Never change this to match the stack region.
  global_region = "us-east-1"
}

# The bucket stays in local.account.state_region (us-east-1) even though the stack itself now deploys
# into us-west-2 — it already exists there, and the backend region has to name the bucket's real home
# or init fails to find it. Deliberately not derived from local.account.aws_region for that reason.
#
# JFrog Cloud trial expired — reverted to S3, the pre-2026-08-11 backend (see commit a18e7e5 for the original
# JFrog switch and its reasoning). No state migration: dev's JFrog-tracked state as of this revert was purely
# from IAM-policy testing, not worth carrying over — this bucket/key starts fresh.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "thor-terraform-state-${local.account.account_id}"
    key          = "thor-${local.environment}/terraform.tfstate"
    region       = local.account.state_region
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
      ManagedBy   = "terraform"
    }
  }
}
EOF
}

inputs = {
  environment   = local.environment
  account_id    = local.account.account_id
  aws_region    = local.account.aws_region
  global_region = local.global_region
}

# dotnet publish before plan/apply/destroy, so archive_file has real code to zip. Skippable via SKIP_LAMBDA_PUBLISH=true — used by CI's apply job, which already has the zip and doesn't need a rebuild.
terraform {
  before_hook "publish_lambda_functions" {
    commands     = ["plan", "apply", "destroy"]
    execute      = ["${get_repo_root()}/scripts/publish-lambda-functions.sh"]
    run_on_error = false
    if           = get_env("SKIP_LAMBDA_PUBLISH", "false") != "true"
  }
}
