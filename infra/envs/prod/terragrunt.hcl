include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}

# Every value the root module accepts is spelled out below, same as envs/dev — only `environment` is left out, root.hcl supplies it.
inputs = {
  # --- network ---
  enable_network       = true
  vpc_cidr             = "10.0.0.0/16"
  az_count             = 2
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  enable_vpc_endpoints = true

  # --- ecs compute ---
  enable_compute            = true
  enable_container_insights = true

  # container_image = "" falls back to that service's own ECR repo at the "latest" tag; set it explicitly once CI promotes a real image. ROLLING, not BLUE_GREEN — the test-traffic listener now exists (nlb.tf), but nothing in the pipeline actually exercises it against green before cutover yet.
  services = {
    thor-api = {
      container_image        = ""
      container_port         = 8080
      cpu                    = 1024
      memory                 = 2048
      desired_count          = 4
      min_healthy_percent    = 100
      max_percent            = 200
      health_check_path      = "/health"
      log_retention_days     = 30
      environment_variables  = {}
      secrets                = {}
      expose_publicly        = true
      nlb_listener_port      = 80
      nlb_test_listener_port = 8081
      deployment_strategy    = "ROLLING"
      bake_time_in_minutes   = 5
    }
    task-api = {
      container_image       = ""
      container_port        = 8080
      cpu                   = 1024
      memory                = 2048
      desired_count         = 4
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
      cpu                   = 1024
      memory                = 2048
      desired_count         = 4
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
  # Prod's domain is a fully separate decision from dev/qa's sphereboard.ai —
  # still unconfirmed, so left empty rather than guessed. See
  # project_thor_domain memory.
  enable_route53 = false
  hosted_zones   = {}

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend          = true
  frontend_price_class     = "PriceClass_100"
  frontend_certificate_key = ""

  # --- database (Aurora PostgreSQL, task-api's) ---
  # Deletion protection on, real final snapshot kept, longer backup retention than dev — prod is not disposable. min/max_capacity are a starting guess, not tuned against real traffic yet.
  aurora_database_name         = "thor_prod_db"
  aurora_master_username       = "thor_admin"
  aurora_engine_version        = "16.13"
  aurora_min_capacity          = 1
  aurora_max_capacity          = 4
  aurora_backup_retention_days = 30
  aurora_deletion_protection   = true
  aurora_skip_final_snapshot   = false

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
