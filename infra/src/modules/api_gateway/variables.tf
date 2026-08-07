variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod) — also used as the API Gateway stage name"
}

variable "service_name" {
  type        = string
  description = "Name of the service this API Gateway fronts (currently always \"thor\", the only publicly-exposed service)"
  default     = "thor"
}

variable "nlb_listener_arn" {
  type        = string
  description = "ARN of the NLB's production listener — an HTTP API v2 private integration targets the listener ARN directly, not a DNS-based URI"
}

variable "vpc_id" {
  type        = string
  description = "VPC the NLB lives in — the VPC Link's ENIs and their security group are provisioned here"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Subnets the VPC Link's ENIs are placed in — same private subnets the NLB itself uses"
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}

variable "enable_authorizer" {
  type        = bool
  description = "Locks proxy methods behind the Lambda API-key authorizer instead of leaving them open (authorization = NONE)"
  default     = false
}

variable "authorizer_lambda_invoke_arn" {
  type        = string
  description = "Lambda authorizer's invoke ARN — only used when enable_authorizer is true"
  default     = ""
}

variable "authorizer_lambda_function_name" {
  type        = string
  description = "Lambda authorizer's function name — only used when enable_authorizer is true, to grant API Gateway invoke permission"
  default     = ""
}
