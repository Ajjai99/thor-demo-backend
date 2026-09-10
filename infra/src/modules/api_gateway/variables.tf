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

variable "authorizer_lambda_invoke_arn" {
  type        = string
  description = "Lambda authorizer's invoke ARN"
}

variable "authorizer_lambda_function_name" {
  type        = string
  description = "Lambda authorizer's function name — grants API Gateway invoke permission"
}

variable "aws_region" {
  type        = string
  description = "Region this API lives in — builds the execute-api origin hostname for cdn.tf without a live data source lookup. Note this is the *origin's* region; the distribution itself is global and its certificate must be us-east-1 regardless."
}

variable "domain_name" {
  type        = string
  description = "Public hostname for this API, e.g. api.dev.hartech.online — served by the CloudFront distribution in cdn.tf, which is what owns the name. \"\" (default) leaves the distribution on its own *.cloudfront.net domain: no alias record and no custom certificate."
  default     = ""
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate covering domain_name — must be in us-east-1, which CloudFront requires of every distribution regardless of which region this API runs in. Required when domain_name is set, unused otherwise."
  default     = ""
}

variable "zone_id" {
  type        = string
  description = "Hosted zone domain_name's alias record gets created in. Required when domain_name is set, unused otherwise."
  default     = ""
}

variable "cdn_price_class" {
  type        = string
  description = "CloudFront price class for this API's distribution — controls which edge locations serve it"
  default     = "PriceClass_100"
}

variable "cdn_waf_rate_limit" {
  type        = number
  description = "WAF rate-limit threshold for this API's distribution: requests from a single IP in a rolling 5-minute window before it's blocked. Tuned separately from the frontend's, since API call rates per client look nothing like browser traffic."
  default     = 2000
}

variable "cors_allow_origins" {
  type        = list(string)
  description = "Origins allowed to call this API from a browser, as full origins including scheme (e.g. [\"https://dev.hartech.online\"]) — the frontend's own hostname, which is cross-origin to the API's. [] (default) omits cors_configuration entirely, leaving preflight unanswered, which is fine for a server-to-server-only API."
  default     = []
}

variable "cors_allow_methods" {
  type        = list(string)
  description = "Methods advertised in preflight responses. Should cover whatever the routes actually expose (integration.tf's GET/POST today) plus OPTIONS. Unused when cors_allow_origins is empty."
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allow_headers" {
  type        = list(string)
  description = "Headers a browser is allowed to send. x-api-key matters specifically — it's the authorizer's identity source (authorizer.tf), so omitting it here would let preflight pass and then fail the real request. Unused when cors_allow_origins is empty."
  default     = ["content-type", "x-api-key", "authorization"]
}

variable "cors_max_age" {
  type        = number
  description = "How long (seconds) a browser may cache this API's preflight response. Unused when cors_allow_origins is empty."
  default     = 300
}

variable "tls_server_name" {
  type        = string
  description = "Hostname to verify against the NLB listener's cert (its CN/SAN) and send via SNI, for NLB <-> ECS TLS re-encryption. \"\" (default) leaves the integration on plain HTTP, matching the NLB's own default (non-TLS) listener — must agree with whatever set the NLB's cert (main.tf's backend_route53)."
  default     = ""
}

variable "global_region" {
  type        = string
  description = "Region the CLOUDFRONT-scoped WAFv2 web ACL is created through (us-east-1). Not this module's own region: see cdn_waf.tf."
}
