locals {
  environment = basename(get_original_terragrunt_dir())

  account_map = {
    dev = {
      account_id = "853973692277" # Account A, shared with qa — provide aws-account-id
      aws_region = "us-east-1"
    }
    qa = {
      account_id = "853973692277" # Account A, shared with dev — provide aws-account-id
      aws_region = "us-east-1"
    }
    prod = {
      account_id = "ACCOUNT-ID" # Account B, isolated from dev/qa — provide aws-account-id
      aws_region = "us-east-1"
    }
  }

  account = local.account_map[local.environment]

  # JFrog Cloud state backend. Changing jfrog_hostname also means updating infra.yml's TF_TOKEN_... line to match.
  jfrog_hostname = get_env("JFROG_HOSTNAME", "trialc6mgth.jfrog.io")
  repo_name      = get_env("TF_BACKEND_REPOSITORY", "terraform-state-local")

  # Local-testing escape hatch only — CI never sets TF_BACKEND, so it always
  # gets the JFrog backend above. Set TF_BACKEND=s3 (+ TF_BACKEND_S3_BUCKET)
  # to test against a throwaway S3 backend instead, without needing a JFrog
  # access token. Revert to jfrog (the default) once done testing.
  backend_type      = get_env("TF_BACKEND", "jfrog")
  s3_backend_bucket = get_env("TF_BACKEND_S3_BUCKET", "")
  s3_backend_region = get_env("TF_BACKEND_S3_REGION", local.account.aws_region)

  # Heredocs inside a ternary's branches don't parse reliably in HCL, so each
  # backend's content is its own local, selected below by a plain ternary.
  backend_s3_contents = <<-EOF
    terraform {
      backend "s3" {
        bucket       = "thor-terraform-state-${local.s3_backend_bucket}"
        key          = "thor-${local.environment}/terraform.tfstate"
        region       = "${local.s3_backend_region}"
        use_lockfile = true
        encrypt      = true
      }
    }
  EOF

  backend_jfrog_contents = <<-EOF
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

# Backend config via generate
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.backend_type == "s3" ? local.backend_s3_contents : local.backend_jfrog_contents
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

# dotnet publish before plan/apply/destroy, so archive_file has real code to zip. Skippable via SKIP_LAMBDA_PUBLISH=true — used by CI's apply job, which already has the zip and doesn't need a rebuild.
terraform {
  before_hook "publish_lambda_functions" {
    commands     = ["plan", "apply", "destroy"]
    execute      = ["${get_repo_root()}/scripts/publish-lambda-functions.sh"]
    run_on_error = false
    if           = get_env("SKIP_LAMBDA_PUBLISH", "false") != "true"
  }
}
