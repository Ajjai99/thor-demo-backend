include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}

# Every value the root module accepts is spelled out below, same as envs/dev — only `environment` is left out, root.hcl supplies it.
inputs = {
  # --- network ---
  # qa's own VPC — 10.1.0.0/16 to stay non-overlapping with dev's 10.0.0.0/16 (same AWS account).
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
    thor-api = {
      container_image = ""
      # 443, thor-api terminates the NLB's re-encrypted TLS session itself (self-signed cert, see Program.cs).
      container_port         = 443
      cpu                    = 512
      memory                 = 1024
      desired_count          = 2
      min_healthy_percent    = 100
      max_percent            = 200
      health_check_path      = "/health"
      log_retention_days     = 30
      environment_variables  = {}
      secrets                = {}
      expose_via_nlb         = true
      nlb_listener_port      = 443
      nlb_test_listener_port = 8082
      deployment_strategy    = "ROLLING"
      bake_time_in_minutes   = 5
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
      expose_via_nlb        = false
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
      expose_via_nlb        = false
      deployment_strategy   = "ROLLING"
      bake_time_in_minutes  = 5
    }
  }

  # --- route53 + acm (hosted zones with their certificates nested) ---
  # Off until dev's apply has actually created cndemo.com's zone — apex
  # below is a lookup (create_zone = false), not a create, so it 404s until
  # then. Turn this on once that's confirmed live.
  enable_route53 = false

  hosted_zones = {
    # Same apex zone dev creates — looked up here, not created, so this
    # doesn't fight dev over who owns cndemo.com.
    apex = {
      zone_name    = local.apex_domain
      create_zone  = false
      certificates = {}
    }

    thor = {
      zone_name        = "qa.cndemo.com"
      parent_zone_name = local.apex_domain
      certificates = {
        frontend = {
          domain_name = "qa.cndemo.com"
        }
        api_gateway = {
          domain_name = "api.qa.cndemo.com"
        }
        # NLB's TLS listener cert (re-encryption) — CN/SNI only, no DNS record needed.
        backend = {
          domain_name = "backend.qa.cndemo.com"
        }
      }
    }
  }

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend          = true
  frontend_price_class     = "PriceClass_100"
  frontend_certificate_key = "thor/frontend"

  # --- api gateway custom domain ---
  api_gateway_certificate_key = "thor/api_gateway"

  # --- nlb <-> ecs TLS re-encryption ---
  backend_certificate_key = "thor/backend"

  # --- database (Aurora PostgreSQL, task-api's) ---
  aurora_database_name         = "thor_qa_db"
  aurora_master_username       = "thor_admin"
  aurora_engine_version        = "16.13"
  aurora_min_capacity          = 0.5
  aurora_max_capacity          = 1
  aurora_backup_retention_days = 7
  aurora_deletion_protection   = true
  aurora_skip_final_snapshot   = true

  # --- lambda authorizer ---
  authorizer_lambda_runtime     = "dotnet10"
  authorizer_lambda_timeout     = 60  # seconds
  authorizer_lambda_memory_size = 512 # MB
  # get_repo_root() stays valid across any Terragrunt cache copy. dotnet publish must have already written here.
  authorizer_source_dir = "${get_repo_root()}/backend/functions/Thor.Authorizer/publish"

  tags = {}
}
