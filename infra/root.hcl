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

  jfrog_hostname = get_env("JFROG_HOSTNAME")
  repo_name      = get_env("JFROG_STATE_BACKEND_REPOSITORY")
}

# Backend config via generate
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
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
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

# server_url stays a literal Terraform variable reference (not a Terragrunt-resolved value) so it can keep
# varying per environment via each env's terragrunt.hcl inputs, same as aws's region above does not.
provider "acme" {
  server_url = var.acme_server_url
}
EOF
}

inputs = {
  environment = local.environment

  # Terragrunt only copies infra/src into .terragrunt-cache, so a Terraform-side file() call can't reach
  # repo-root scripts/ — read here instead, where get_repo_root() still points at the real checkout, and pass
  # the content through as a plain string input.
  tls_sidecar_entrypoint_script = file("${get_repo_root()}/scripts/tls-sidecar-entrypoint.sh")
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
