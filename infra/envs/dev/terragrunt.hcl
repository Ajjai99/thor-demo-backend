include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}

# Every value the root module accepts is spelled out below instead of relying on a default in infra/src/variables.tf; only `environment` is left out, since infra/root.hcl already supplies it for every environment.
inputs = {
  # --- network ---
  enable_network       = true
  vpc_cidr             = "10.0.0.0/16"
  az_count             = 2
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  enable_vpc_endpoints = true

  # --- ecs compute ---
  # false until a real image has been pushed to each ECR repo below — the cluster/namespace/repos are created regardless.
  enable_compute            = true
  enable_container_insights = true

  # container_image = "" falls back to that service's own ECR repo at the "latest" tag; set it explicitly to pin a specific tag.
  services = {
    thor-api = {
      container_image        = ""
      container_port         = 8080
      cpu                    = 512  # 0.5 vCPU
      memory                 = 1024 # 1 GB
      desired_count          = 2
      min_healthy_percent    = 100
      max_percent            = 200
      health_check_path      = "/health"
      log_retention_days     = 30
      environment_variables  = {}
      secrets                = {}
      expose_publicly        = true
      nlb_listener_port      = 80
      nlb_test_listener_port = 8081
      deployment_strategy    = "BLUE_GREEN"
      bake_time_in_minutes   = 10
    }
    task-api = {
      container_image       = ""
      container_port        = 8080
      cpu                   = 512  # 0.5 vCPU
      memory                = 1024 # 1 GB
      desired_count         = 2
      min_healthy_percent   = 100
      max_percent           = 200
      health_check_path     = "/health"
      log_retention_days    = 30
      environment_variables = {}
      secrets               = {}
      expose_publicly       = false
      deployment_strategy   = "BLUE_GREEN"
      bake_time_in_minutes  = 10
    }
    intelligence-engine = {
      container_image       = ""
      container_port        = 8080
      cpu                   = 512  # 0.5 vCPU
      memory                = 1024 # 1 GB
      desired_count         = 2
      min_healthy_percent   = 100
      max_percent           = 200
      health_check_path     = "/health"
      log_retention_days    = 30
      environment_variables = {}
      secrets               = {}
      expose_publicly       = false
      deployment_strategy   = "BLUE_GREEN"
      bake_time_in_minutes  = 10
    }
  }

  # --- route53 + acm (hosted zones with their certificates nested) ---
  # TEMPORARY test override: varunsimha.com is already registered in this
  # account, so it's usable to prove the new generic route53/acm modules
  # work end-to-end before sphereboard.ai is confirmed. Revert to the
  # dev.sphereboard.ai / false values below once that's real — don't leave
  # this pointed at varunsimha.com.
  #   enable_route53 = false
  #   hosted_zones = {
  #     thor = {
  #       zone_name = "dev.sphereboard.ai"
  #       certificates = {
  #         frontend    = { domain_name = "dev.sphereboard.ai" }
  #         api_gateway = { domain_name = "api.dev.sphereboard.ai" }
  #       }
  #     }
  #   }
  enable_route53 = true

  hosted_zones = {
    # Apex zone — no certificates of its own, exists only so the "dev" NS
    # delegation record (added manually below, same as SPHERE IT would for
    # real) has somewhere to live.
    apex = {
      zone_name    = "cndemo.com" # Dev 
      certificates = {}
    }

    thor = {
      zone_name = "dev.cndemo.com"
      certificates = {
        frontend = {
          domain_name = "dev.cndemo.com"
        }
        api_gateway = {
          domain_name = "api.dev.cndemo.com"
        }
      }
    }
  }

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend          = true
  frontend_price_class     = "PriceClass_100"
  frontend_certificate_key = "thor/frontend"

  # --- database (Aurora PostgreSQL, task-api's) ---
  # Low capacity + no deletion protection — dev is throwaway, cost-optimized.
  aurora_database_name         = "thor_dev_db"
  aurora_master_username       = "thor_admin"
  aurora_engine_version        = "16.13"
  aurora_min_capacity          = 0.5
  aurora_max_capacity          = 1
  aurora_backup_retention_days = 7
  aurora_deletion_protection   = true
  aurora_skip_final_snapshot   = true

  # --- rds proxy ---
  enable_rds_proxy = true

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
