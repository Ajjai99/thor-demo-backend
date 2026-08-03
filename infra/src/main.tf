# Root module composing every infra component for one environment into a single Terraform state, one per environment via Terragrunt.

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

# Aurora Postgres (RDS Proxy) + Neptune, owned by task-api, are planned separately as their own module blocks here.
