include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}

locals {
  root_domain = "susdemo.site"
}


# Every value the root module accepts is spelled out below, same as envs/dev — only `environment` is left out, root.hcl supplies it.
inputs = {
  # --- network ---
  # qa gets its own VPC, separate from dev's (10.0.0.0/16) — no shared/borrowed network between environments.
  enable_network       = true
  vpc_cidr             = "10.1.0.0/16"
  az_count             = 2
  public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  enable_vpc_endpoints = true

  # --- ecs compute ---
  enable_compute            = false
  enable_container_insights = true

  # container_image = "" falls back to that service's own ECR repo at the "latest" tag; set it explicitly to pin a specific tag.
  services = {
    thor = {
      container_image       = ""
      container_port        = 8080
      cpu                   = 512
      memory                = 1024
      desired_count         = 2
      min_healthy_percent   = 100
      max_percent           = 200
      health_check_path     = "/health"
      log_retention_days    = 30
      environment_variables = {}
      secrets               = {}
      expose_publicly       = true
      nlb_listener_port     = 80
      deployment_strategy   = "ROLLING"
      bake_time_in_minutes  = 5
    }
    task-api = {
      container_image       = ""
      container_port        = 8080
      cpu                   = 512
      memory                = 1024
      desired_count         = 2
      min_healthy_percent   = 100
      max_percent           = 200
      health_check_path     = "/health"
      log_retention_days    = 30
      environment_variables = {}
      secrets               = {}
      expose_publicly       = false
      deployment_strategy   = "ROLLING"
      bake_time_in_minutes  = 5
    }
    intelligence-engine = {
      container_image       = ""
      container_port        = 8080
      cpu                   = 512
      memory                = 1024
      desired_count         = 2
      min_healthy_percent   = 100
      max_percent           = 200
      health_check_path     = "/health"
      log_retention_days    = 30
      environment_variables = {}
      secrets               = {}
      expose_publicly       = false
      deployment_strategy   = "ROLLING"
      bake_time_in_minutes  = 5
    }
  }

  # --- route53 + acm (hosted zones with their certificates nested) ---
  # TEMPORARY test override, same as dev: susdemo.site is already registered
  # and its apex zone already exists (created by envs/dev). qa.susdemo.site
  # is a subdomain of that same apex, not a new apex of its own — after
  # applying route53 here, the resulting zone's 4 name servers need to be
  # added manually as an NS record set for "qa" inside the existing
  # susdemo.site apex zone (same manual delegation step already done for
  # "dev"). Revert to the qa.sphereboard.ai / false values below once that
  # domain is confirmed — don't leave this pointed at susdemo.site.
  #   enable_route53 = false
  #   hosted_zones = {
  #     thor = {
  #       zone_name = "qa.sphereboard.ai"
  #       certificates = {
  #         frontend = {
  #           domain_name               = "qa.sphereboard.ai"
  #           subject_alternative_names = ["api.qa.sphereboard.ai"]
  #         }
  #       }
  #     }
  #   }
  enable_route53 = true

  hosted_zones = {
    thor = {
      zone_name = "qa.${local.root_domain}"

      certificates = {
        frontend = {
          domain_name = "qa.${local.root_domain}"
        }
        api_gateway = {
          domain_name = "api.qa.${local.root_domain}"
        }
      }
    }
  }

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend          = true
  frontend_price_class     = "PriceClass_100"
  frontend_certificate_key = "thor/frontend"

  # --- database (Aurora PostgreSQL, task-api's) ---
  aurora_database_name         = "thor_qa_db"
  aurora_master_username       = "thor_admin"
  aurora_engine_version        = "16.13"
  aurora_min_capacity          = 0.5
  aurora_max_capacity          = 1
  aurora_backup_retention_days = 7
  aurora_deletion_protection   = true
  aurora_skip_final_snapshot   = true

  # --- rds proxy ---
  enable_rds_proxy = true

  # --- api gateway custom domain ---
  api_gateway_certificate_key = "thor/api_gateway"

  # --- api gateway authorizer ---
  enable_authorizer = true

  # --- lambda authorizer ---
  authorizer_lambda_runtime     = "dotnet10"
  authorizer_lambda_timeout     = 60  # seconds
  authorizer_lambda_memory_size = 512 # MB
  # get_repo_root() stays valid across any Terragrunt cache copy. dotnet publish must have already written here.
  authorizer_source_dir = "${get_repo_root()}/backend/functions/Thor.Authorizer/publish"

  tags = {}
}
