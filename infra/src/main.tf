# Root module composing every infra component for one environment into a single Terraform state, one per environment via Terragrunt.

# required_providers deliberately isn't declared here — Terragrunt's own
# generate block (root.hcl) already writes a required_providers block into
# this same directory via its generated provider.tf, and Terraform rejects
# two required_providers blocks in one module. required_version alone is
# what tflint actually flags as missing for this file anyway (root main.tf
# only composes module blocks, no direct aws_* resources of its own).
terraform {
  required_version = ">= 1.15"
}

# Disabled via enable_network when this environment borrows dev's VPC instead of creating its own (e.g. qa).
module "network" {
  count = var.enable_network ? 1 : 0

  source = "./modules/network"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  az_count             = var.az_count
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_vpc_endpoints = var.enable_vpc_endpoints
  tags                 = var.tags
}

locals {
  vpc_id             = var.enable_network ? module.network[0].vpc_id : var.dev_vpc_id
  vpc_cidr_effective = var.enable_network ? module.network[0].vpc_cidr : var.dev_vpc_cidr
  public_subnet_ids  = var.enable_network ? module.network[0].public_subnet_ids : var.dev_public_subnet_ids
  private_subnet_ids = var.enable_network ? module.network[0].private_subnet_ids : var.dev_private_subnet_ids
}

# Always instantiated — enable_compute is passed through and gates the services/target-group/IAM internally, not this module block, since the cluster/namespace/ECR repos must exist before enable_compute can turn on.
module "ecs" {
  source = "./modules/ecs"

  environment               = var.environment
  enable_compute            = var.enable_compute
  vpc_id                    = local.vpc_id
  vpc_cidr                  = local.vpc_cidr_effective
  private_subnet_ids        = local.private_subnet_ids
  enable_container_insights = var.enable_container_insights

  services = var.services

  tags = var.tags
}

# Independent of network/compute — a private S3 bucket + CloudFront (OAC)
# distribution for the static thor-demo-frontend SPA. The GitHub Actions
# deploy role that syncs to it is bootstrapped separately by
# scripts/create-deploy-role.sh, not created here — see that script's header
# for why (its CloudFront distribution ID isn't known until this applies).
module "frontend" {
  count = var.enable_frontend ? 1 : 0

  source = "./modules/frontend"

  environment = var.environment
  price_class = var.frontend_price_class

  tags = var.tags
}

# Gated by enable_compute — needs thor's NLB listener to exist first (module.ecs.nlb_arns/nlb_dns_names are only populated once local.public_services is non-empty).
module "api_gateway" {
  count = var.enable_compute ? 1 : 0

  source = "./modules/api_gateway"

  environment       = var.environment
  service_name      = "thor"
  nlb_arn           = module.ecs.nlb_arns["thor"]
  nlb_dns_name      = module.ecs.nlb_dns_names["thor"]
  nlb_listener_port = var.services["thor"].nlb_listener_port

  tags = var.tags
}

# task-api's database. Always instantiated, same reasoning as module.ecs's
# cluster/namespace/ECR repos — a database shouldn't require application
# compute to exist first, and standing it up early lets migrations/seeding
# happen before enable_compute ever turns on. task_api_security_group_id is
# null until enable_compute creates task-api's own security group; the
# module's ingress rule is skipped entirely until then, not an error.
module "aurora" {
  source = "./modules/aurora"

  environment                = var.environment
  vpc_id                     = local.vpc_id
  vpc_cidr                   = local.vpc_cidr_effective
  private_subnet_ids         = local.private_subnet_ids
  create_task_api_ingress    = var.enable_compute
  task_api_security_group_id = var.enable_compute ? module.ecs.service_security_group_ids["task-api"] : null

  database_name         = var.aurora_database_name
  master_username       = var.aurora_master_username
  engine_version        = var.aurora_engine_version
  min_capacity          = var.aurora_min_capacity
  max_capacity          = var.aurora_max_capacity
  backup_retention_days = var.aurora_backup_retention_days
  deletion_protection   = var.aurora_deletion_protection
  skip_final_snapshot   = var.aurora_skip_final_snapshot

  tags = var.tags
}

# RDS Proxy and Neptune remain future work — see this repo's CI/CD memory for why they're deliberately excluded from this pass.
