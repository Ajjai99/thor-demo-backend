variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod) — also used as the API Gateway stage name"
}

variable "service_name" {
  type        = string
  description = "Name of the service this API Gateway fronts (currently always \"thor-api\", the only publicly-exposed service)"
  default     = "thor-api"
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

variable "domain_name" {
  type        = string
  description = "Custom hostname to map this API to, e.g. api.dev.cndemo.com. \"\" (default) leaves the API reachable only via its default execute-api URL — no custom domain, mapping, or alias records get created."
  default     = ""
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate covering domain_name — must be REGIONAL (same region as this API), not the us-east-1-only certs CloudFront requires, unless this API also happens to run in us-east-1. Required when domain_name is set, unused otherwise."
  default     = ""
}

variable "zone_id" {
  type        = string
  description = "Hosted zone domain_name's alias records get created in. Required when domain_name is set, unused otherwise."
  default     = ""
}
