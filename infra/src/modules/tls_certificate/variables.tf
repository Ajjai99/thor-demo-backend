variable "root_domain" {
  type        = string
  description = "Registered domain with a Route 53 public hosted zone in this account, used for the certificate's DNS-01 challenge."
}

variable "common_name" {
  type        = string
  description = "Hostname the certificate is issued for — must match whatever validates it downstream (e.g. API Gateway's server_name_to_verify), or the trust check fails on a hostname mismatch even with a valid cert."
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}
