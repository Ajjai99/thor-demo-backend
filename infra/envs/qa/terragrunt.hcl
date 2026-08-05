include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}


dependency "dev" {
  config_path = "../dev"

  mock_outputs = {
    vpc_id             = "vpc-mock00000000"
    vpc_cidr           = "10.255.255.0/24"
    public_subnet_ids  = ["subnet-mockpub1", "subnet-mockpub2"]
    private_subnet_ids = ["subnet-mockpriv1", "subnet-mockpriv2"]
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

# Every value the root module accepts is spelled out below instead of relying on a default in infra/src/variables.tf — same convention as envs/dev/terragrunt.hcl; only `environment` is left out, since infra/root.hcl already supplies it for every environment.
inputs = {
  # --- network ---
  # qa borrows dev's VPC instead of creating its own — vpc_cidr / public_subnet_cidrs / private_subnet_cidrs are unused while enable_network is false; dev's values apply instead.
  enable_network = false

  dev_vpc_id             = dependency.dev.outputs.vpc_id
  dev_vpc_cidr           = dependency.dev.outputs.vpc_cidr
  dev_public_subnet_ids  = dependency.dev.outputs.public_subnet_ids
  dev_private_subnet_ids = dependency.dev.outputs.private_subnet_ids

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

  # --- frontend (static SPA: S3 + CloudFront) ---
  enable_frontend      = true
  frontend_price_class = "PriceClass_100"

  tags = {}
}
