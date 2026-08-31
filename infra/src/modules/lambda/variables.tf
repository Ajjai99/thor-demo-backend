variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod)"
}

variable "aurora_cluster_arn" {
  type        = string
  description = "Aurora cluster ARN — RDS Data API's resourceArn parameter, where hashed API keys are looked up"
}

variable "aurora_secret_arn" {
  type        = string
  description = "Aurora master user secret ARN — RDS Data API's secretArn parameter"
}

variable "aurora_database_name" {
  type        = string
  description = "Database name the authorizer queries for hashed API keys"
}

variable "authorizer_salt_secret_arn" {
  type        = string
  description = "Secrets Manager ARN of the PBKDF2 salt — passed to the function as THOR_AUTHORIZER_SALT_SECRET_ID and used to scope secretsmanager:GetSecretValue"
}

variable "iam_permissions_boundary_arn" {
  type        = string
  description = "ARN of the Console-created thor-<environment>-role-boundary policy (see docs/infra_pipeline_setup_guide.md) — required on the authorizer's IAM role's permissions_boundary argument, or the deploy role's own iam:CreateRole grant rejects the call."
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}

variable "runtime" {
  type        = string
  description = "Lambda runtime — must match the handler format (Assembly::Namespace.Class::Method) if changed"
  default     = "dotnet10"
}

variable "timeout" {
  type        = number
  description = "Function timeout in seconds"
  default     = 5
}

variable "memory_size" {
  type        = number
  description = "Function memory in MB"
  default     = 256
}

variable "authorizer_source_dir" {
  type        = string
  description = "Absolute path to lambda authorizer code"
}
