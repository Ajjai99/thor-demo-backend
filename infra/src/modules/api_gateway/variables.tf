variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod) — also used as the API Gateway stage name"
}

variable "service_name" {
  type        = string
  description = "Name of the service this API Gateway fronts (currently always \"thor\", the only publicly-exposed service)"
  default     = "thor"
}

variable "nlb_arn" {
  type        = string
  description = "ARN of the NLB the VPC Link attaches to"
}

variable "nlb_dns_name" {
  type        = string
  description = "DNS name of the NLB — the VPC Link integration's uri targets this directly, not the ARN"
}

variable "nlb_listener_port" {
  type        = number
  description = "Port the NLB's production listener listens on"
  default     = 80
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}
