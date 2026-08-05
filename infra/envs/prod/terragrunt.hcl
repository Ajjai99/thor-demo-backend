include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}

# Every value the root module accepts is spelled out below instead of relying on a default in infra/src/variables.tf — same convention as envs/dev/terragrunt.hcl; only `environment` is left out, since infra/root.hcl already supplies it for every environment.
inputs = {
  # --- network ---
  enable_network       = true
  vpc_cidr             = "10.2.0.0/16"
  az_count             = 2
  public_subnet_cidrs  = ["10.2.0.0/24", "10.2.1.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
  enable_vpc_endpoints = true

  # --- ecs compute ---
  enable_compute            = true
  enable_container_insights = true

  # container_image = "" falls back to that service's own ECR repo at the "latest" tag; set it explicitly once CI promotes a real image. ROLLING, not BLUE_GREEN — the test-traffic gate that makes blue/green's automatic cutover safe isn't built yet.
  services = {
    thor = {
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
      expose_publicly       = true
      nlb_listener_port     = 80
      deployment_strategy   = "ROLLING"
      bake_time_in_minutes  = 5
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

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend      = true
  frontend_price_class = "PriceClass_100"

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

  tags = {}
}
