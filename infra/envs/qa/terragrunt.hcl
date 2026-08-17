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

# Every value the root module accepts is spelled out below, same as envs/dev — only `environment` is left out, root.hcl supplies it.
inputs = {
  # --- network ---
  # qa borrows dev's VPC — vpc_cidr/subnet_cidrs below are unused while enable_network is false.
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
    thor-api = {
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
      nlb_test_listener_port = 8081
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
  # Off until the domain is confirmed and SPHERE IT has added the delegation
  # NS record for qa.sphereboard.ai — see project_thor_domain memory. Values
  # below are the working assumption, not final.
  enable_route53 = false

  hosted_zones = {
    thor = {
      zone_name = "qa.sphereboard.ai"

      certificates = {
        frontend = {
          domain_name               = "qa.sphereboard.ai"
          subject_alternative_names = ["api.qa.sphereboard.ai"]
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
