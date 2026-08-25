variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod)"
}

# --- network ---

variable "enable_network" {
  type        = bool
  description = "Whether to create this environment's own VPC. Set false to borrow dev's VPC instead (see dev_* variables) and skip that VPC's endpoint/NAT costs entirely."
  default     = true
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC. Unused when enable_network is false."
  default     = ""
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to span"
  default     = 2
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets, one per AZ. Unused when enable_network is false."
  default     = []
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets, one per AZ. Unused when enable_network is false."
  default     = []
}

variable "enable_vpc_endpoints" {
  type        = bool
  description = "Create gateway/interface VPC endpoints instead of NAT Gateway egress"
  default     = true
}

# --- dev's network (used only when enable_network = false) ---

variable "dev_vpc_id" {
  type        = string
  description = "dev's VPC ID, to deploy compute into when this environment doesn't create its own (passed in via a Terragrunt dependency block)"
  default     = null
}

variable "dev_vpc_cidr" {
  type        = string
  description = "CIDR of dev's VPC — scopes the compute security group's egress"
  default     = null
}

variable "dev_public_subnet_ids" {
  type        = list(string)
  description = "dev's public subnet IDs, for the ALB"
  default     = []
}

variable "dev_private_subnet_ids" {
  type        = list(string)
  description = "dev's private subnet IDs, for the ECS tasks"
  default     = []
}

# --- compute (shared ECS cluster running thor-api, task-api, intelligence-engine) ---

variable "enable_compute" {
  type        = bool
  description = "Whether to create the three ECS services (task defs, ECS services, NLB/target groups, per-service IAM/SG). The ECS cluster, Service Connect namespace, and ECR repos are created regardless of this flag — set false to bring up an environment's cluster/registry only, before real images exist to reference."
  default     = true
}

variable "services" {
  description = "Per-service configuration for the shared ECS cluster, keyed by service name. Must define thor-api, task-api, and intelligence-engine, with thor-api the only one setting expose_via_nlb = true (a private NLB reached via VPC Link from API Gateway, not the internet directly — no ALB). deployment_strategy=BLUE_GREEN is a per-deploy toggle (reserved for DB-schema-change deploys per deployment_strategy_plan.md), not a fixed per-service default."
  type = map(object({
    container_image        = string
    container_port         = number
    cpu                    = number
    memory                 = number
    desired_count          = number
    min_healthy_percent    = number
    max_percent            = number
    health_check_path      = string
    log_retention_days     = number
    environment_variables  = map(string)
    secrets                = map(string)
    expose_via_nlb         = bool
    nlb_listener_port      = optional(number)
    nlb_test_listener_port = optional(number, 8082)
    deployment_strategy    = string
    bake_time_in_minutes   = number
  }))

  validation {
    condition     = alltrue([for k in ["thor-api", "task-api", "intelligence-engine"] : contains(keys(var.services), k)])
    error_message = "var.services must define an entry for each of: thor-api, task-api, intelligence-engine."
  }

  validation {
    condition     = contains(keys(var.services), "thor-api") ? var.services["thor-api"].expose_via_nlb == true : true
    error_message = "var.services.thor-api.expose_via_nlb must be true — thor-api is the only internet-facing service; task-api and intelligence-engine must stay internal."
  }

  validation {
    condition     = alltrue([for k, v in var.services : contains(["ROLLING", "BLUE_GREEN"], v.deployment_strategy)])
    error_message = "deployment_strategy must be either \"ROLLING\" or \"BLUE_GREEN\" for every service."
  }
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable ECS Container Insights on the cluster"
  default     = true
}

variable "tls_sidecar_entrypoint_script" {
  type        = string
  description = "Contents of scripts/tls-sidecar-entrypoint.sh — read by root.hcl (outside Terragrunt's infra/src copy boundary) and passed in as a string, since the ecs module can't reach repo-root files with file()."
}

# --- TLS sidecar certificate (tls_certificate.tf, Let's Encrypt via Route53 DNS-01) ---

variable "acme_root_domain" {
  type        = string
  description = "Registered domain with a Route 53 public hosted zone in this account, used for the sidecar cert's DNS-01 challenge. The cert's hostname is \"<service>-<environment>.<this domain>\", e.g. thor-api-dev.cndemo.com."
}

variable "acme_server_url" {
  type        = string
  description = "ACME directory URL. Use Let's Encrypt's staging endpoint (https://acme-staging-v02.api.letsencrypt.org/directory) until the flow is confirmed working — staging certs aren't publicly trusted, so API Gateway's tls_config will still reject them, but staging avoids burning the real production issuance rate limit while testing. Switch to https://acme-v02.api.letsencrypt.org/directory once verified."
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}

# --- frontend (static SPA: S3 + CloudFront) ---

variable "enable_frontend" {
  type        = bool
  description = "Whether to create the frontend S3 bucket + CloudFront distribution for thor-demo-frontend"
  default     = true
}

variable "frontend_price_class" {
  type        = string
  description = "CloudFront price class for the frontend distribution"
  default     = "PriceClass_100"
}

# --- api gateway authorizer (Lambda, validates connector API keys against Aurora) ---

variable "enable_authorizer" {
  type        = bool
  description = "Locks the API Gateway proxy behind the Lambda API-key authorizer instead of leaving it open (authorization = NONE). Off by default until real authorizer code and seeded API keys exist."
  default     = false
}

variable "authorizer_lambda_runtime" {
  type        = string
  description = "Authorizer Lambda runtime — must match the handler format if changed"
  default     = "dotnet10"
}

variable "authorizer_lambda_timeout" {
  type        = number
  description = "Authorizer Lambda timeout in seconds"
  default     = 5
}

variable "authorizer_lambda_memory_size" {
  type        = number
  description = "Authorizer Lambda memory in MB"
  default     = 256
}

variable "authorizer_source_dir" {
  type        = string
  description = "Absolute path to lambda authorizer code"
}

# --- database (Aurora PostgreSQL, module.aurora — task-api's database) ---
# One cluster per environment, not a map like `services` — RDS Proxy and per-tenant credentials are out of scope for now.

variable "aurora_database_name" {
  type        = string
  default     = ""
  description = "Initial database name created on the Aurora cluster. \"\" falls back to \"thor_<environment>_db\" (module.aurora computes this)."
}

variable "aurora_master_username" {
  type        = string
  default     = "thor_admin"
  description = "Master username — the password itself is AWS-managed (Secrets Manager), never set here"
}

variable "aurora_engine_version" {
  type        = string
  default     = "16.13"
  description = "Aurora PostgreSQL engine version — must be >= 16.1 for RDS Data API support"
}

variable "aurora_min_capacity" {
  type        = number
  default     = 0.5
  description = "Serverless v2 minimum ACU"
}

variable "aurora_max_capacity" {
  type        = number
  default     = 1
  description = "Serverless v2 maximum ACU"
}

variable "aurora_backup_retention_days" {
  type        = number
  default     = 7
  description = "Automated backup retention period"
}

variable "aurora_deletion_protection" {
  type        = bool
  default     = false
  description = "Should be true for prod, false for throwaway dev/qa environments"
}

variable "aurora_skip_final_snapshot" {
  type        = bool
  default     = true
  description = "Should be false for prod, true for throwaway dev/qa environments"
}

# --- rds proxy (module.rds_proxy, connection pooling in front of Aurora) ---

variable "enable_rds_proxy" {
  type        = bool
  description = "Whether to create the RDS Proxy in front of Aurora"
  default     = false
}

# Future modules' variables go here.
