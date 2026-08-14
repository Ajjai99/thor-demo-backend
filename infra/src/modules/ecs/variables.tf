variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC to deploy into"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the VPC — scopes each service security group's egress to VPC-only (no NAT/IGW)"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for the ECS tasks"
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable ECS Container Insights on the cluster"
  default     = true
}

variable "enable_compute" {
  type        = bool
  description = "Whether to create the ECS services (task defs, ECS services, NLB/target groups, per-service IAM/SG) for local.active_services. The cluster, Service Connect namespace, and ECR repos (ecr.tf) are created regardless — set false to bring up an environment's cluster/registry only, before real images exist."
  default     = true
}

variable "services" {
  description = "Per-service configuration, keyed by service name (thor, task-api, intelligence-engine). expose_publicly=true gets a private NLB (nlb.tf, thor only) reached via VPC Link from API Gateway, not directly from the internet; services with expose_publicly=false accept traffic only from the public services' security groups, reachable internally via Service Connect using the map key as the client_alias dns_name. deployment_strategy=BLUE_GREEN is a per-deploy toggle (deployment_strategy_plan.md reserves it for DB-schema-change deploys) — for a publicly-exposed service it shifts the NLB's production listener between blue/green target groups; for an internal service it's a plain task-set swap."
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
    expose_publicly        = bool
    nlb_listener_port      = optional(number)
    nlb_test_listener_port = optional(number)
    deployment_strategy    = string
    bake_time_in_minutes   = number
  }))

  validation {
    condition     = alltrue([for k, v in var.services : contains(["ROLLING", "BLUE_GREEN"], v.deployment_strategy)])
    error_message = "deployment_strategy must be either \"ROLLING\" or \"BLUE_GREEN\" for every service."
  }

  validation {
    condition     = alltrue([for k, v in var.services : v.bake_time_in_minutes >= 0 && v.bake_time_in_minutes <= 1440])
    error_message = "bake_time_in_minutes must be between 0 and 1440 (24 hours) for every service."
  }
}

variable "cross_account_pull_principal_arns" {
  type        = list(string)
  description = "IAM role ARNs (e.g. a downstream environment's deploy role, possibly in another AWS account) allowed to pull images from this environment's ECR repos. Empty by default — fill in once the downstream role actually exists (e.g. qa's terragrunt.hcl sets this to prod's deploy role ARN once the prod account/role are real)."
  default     = []
}

variable "aurora_cluster_arn" {
  type        = string
  description = "Aurora cluster ARN — RDS Data API's resourceArn parameter for thor/task-api's task role"
}

variable "aurora_secret_arn" {
  type        = string
  description = "Aurora master user secret ARN — RDS Data API's secretArn parameter for thor/task-api's task role"
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}
