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

  # Inert here — only used when enable_network = false, i.e. an environment borrowing dev's VPC.
  dev_vpc_id             = null
  dev_vpc_cidr           = null
  dev_public_subnet_ids  = []
  dev_private_subnet_ids = []

  # --- compute ---
  # false until a real image has been pushed to each ECR repo below — the cluster/namespace/repos are created regardless.
  enable_compute            = true
  enable_container_insights = true

  # container_image = "" falls back to that service's own ECR repo at the "latest" tag; set it explicitly to pin a specific tag.
  services = {
    thor = {
      container_image        = ""
      container_port         = 8080
      cpu                    = 512
      memory                 = 1024
      desired_count          = 2
      min_healthy_percent    = 100
      max_percent            = 200
      health_check_path      = "/health"
      log_retention_days     = 30
      environment_variables  = {}
      secrets                = {}
      expose_publicly        = true
      nlb_listener_port      = 80
      deployment_strategy    = "ROLLING"
      bake_time_in_minutes   = 5
    }
    task-api = {
      container_image        = ""
      container_port         = 8080
      cpu                    = 512
      memory                 = 1024
      desired_count          = 2
      min_healthy_percent    = 100
      max_percent            = 200
      health_check_path      = "/health"
      log_retention_days     = 30
      environment_variables  = {}
      secrets                = {}
      expose_publicly        = false
      deployment_strategy    = "ROLLING"
      bake_time_in_minutes   = 5
    }
    intelligence-engine = {
      container_image        = ""
      container_port         = 8080
      cpu                    = 512
      memory                 = 1024
      desired_count          = 2
      min_healthy_percent    = 100
      max_percent            = 200
      health_check_path      = "/health"
      log_retention_days     = 30
      environment_variables  = {}
      secrets                = {}
      expose_publicly        = false
      deployment_strategy    = "ROLLING"
      bake_time_in_minutes   = 5
    }
  }

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend      = true
  frontend_price_class = "PriceClass_100"

  tags = {}
}

