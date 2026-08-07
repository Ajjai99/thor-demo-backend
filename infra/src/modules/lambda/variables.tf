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
