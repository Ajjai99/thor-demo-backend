variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod)"
}

variable "account_id" {
  type        = string
  description = "AWS account ID this environment deploys into — root.hcl's account_map, supplied via its inputs block. Used to build the thor-<environment>-role-boundary policy's ARN (main.tf) without hardcoding it."
}

variable "aws_region" {
  type        = string
  description = "AWS region this environment deploys into — root.hcl's account_map, supplied via its inputs block. Same value the generated provider block is already configured with; passed through explicitly so modules can reference it (e.g. for awslogs-region in a container's logConfiguration) without a live aws_region data source lookup."
}

# --- network ---

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to span"
  default     = 2
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets, one per AZ"
}

variable "enable_vpc_endpoints" {
  type        = bool
  description = "Create gateway/interface VPC endpoints instead of NAT Gateway egress"
  default     = true
}

# --- compute (shared ECS cluster running thor-api, task-api, intelligence-engine) ---

variable "enable_compute" {
  type        = bool
  description = "Whether to create the three ECS services (task defs, ECS services, NLB/target groups, per-service IAM/SG). The ECS cluster, Service Connect namespace, and ECR repos are created regardless of this flag — set false to bring up an environment's cluster/registry only, before real images exist to reference."
  default     = true
}

variable "enable_ingestion" {
  type        = bool
  description = "Whether to create the ingestion pipeline (S3 -> SQS -> EventBridge Pipe -> CreateManifest Lambda -> Step Functions -> ECS ingestion task, see modules/ingestion). The ECR repo is created regardless of this flag, so an image can be pushed before turning it on — everything else stays off until deliberately enabled."
  default     = false
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

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}

# --- route53 + acm (dynamic hosted zones and certificates) ---
# Off by default until domain names are confirmed and any delegation they
# need (e.g. SPHERE IT adding an NS record for a subdomain) is actually in
# place.

variable "enable_route53" {
  type        = bool
  description = "Whether to create this env's hosted zones + ACM certificates. Leave false until domain names are confirmed and delegated."
  default     = false
}

variable "hosted_zones" {
  description = "Hosted zones and their ACM certificates, nested together for readability. Keyed by an arbitrary logical name (not the domain itself — that's zone_name). Each zone's certificates map is in turn keyed by its own arbitrary logical name, scoped to that zone, so short names like \"api\" can repeat across different zones without colliding. parent_zone_name, if set to another zone's zone_name present in this same map, gets this zone's NS delegation record created automatically in that parent (modules/route53) instead of needing to be pasted in by hand. Flattened into modules/route53 + modules/acm's flat shapes inside main.tf — this nesting is purely a root-level ergonomic choice, not something either module needs to know about. Unused while enable_route53 is false."
  type = map(object({
    zone_name        = string
    create_zone      = optional(bool, true)
    comment          = optional(string, "")
    tags             = optional(map(string), {})
    parent_zone_name = optional(string, "")
    certificates = map(object({
      domain_name               = string
      subject_alternative_names = optional(list(string), [])
    }))
  }))
  default = {}
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

variable "frontend_certificate_key" {
  type        = string
  description = "Which entry in the flattened hosted_zones certificates (key format \"<zone_key>/<cert_key>\", e.g. \"thor/frontend\") the frontend distribution's custom domain + cert come from. \"\" (default) leaves the frontend on CloudFront's default certificate, no alias record created."
  default     = ""
}

variable "api_gateway_certificate_key" {
  type        = string
  description = "Which entry in the flattened hosted_zones certificates (key format \"<zone_key>/<cert_key>\", e.g. \"thor/api_gateway\") the API's custom domain + cert come from. \"\" (default) leaves the API reachable only via its default execute-api URL, no custom domain mapping created."
  default     = ""
}

variable "backend_certificate_key" {
  type        = string
  description = "Which entry in the flattened hosted_zones certificates (key format \"<zone_key>/<cert_key>\", e.g. \"thor/backend\") the NLB's TLS listener cert comes from, for NLB <-> ECS re-encryption. \"\" (default) leaves the NLB on plain TCP and the app on plain HTTP:8080, today's behavior — set only where the re-encryption path is actually wanted (dev only for now)."
  default     = ""
}

# --- api gateway authorizer (Lambda, validates connector API keys against Aurora) ---

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

variable "create_manifest_source_dir" {
  type        = string
  description = "Absolute path to CreateManifest's dotnet publish output"
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

# Future modules' variables go here.
