output "vpc_id" {
  value = local.vpc_id
}

output "vpc_cidr" {
  value = local.vpc_cidr_effective
}

output "public_subnet_ids" {
  value = local.public_subnet_ids
}

output "private_subnet_ids" {
  value = local.private_subnet_ids
}

output "vpc_endpoints_security_group_id" {
  value = var.enable_network ? module.network[0].vpc_endpoints_security_group_id : null
}

# Not guarded by enable_compute — the cluster, namespace, and ECR repos exist regardless of it.
output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "service_connect_namespace" {
  value = module.ecs.service_connect_namespace_name
}

output "ecr_repository_urls" {
  description = "Map of service name -> ECR repository URL, for CI to know where to push images"
  value       = module.ecs.ecr_repository_urls
}

# Guarded because these index the "thor-api" map key, which only exists once enable_compute is true. Output
# names kept as thor_* (stable external interface referring to "the main/public service") even though the
# underlying service key is thor-api.
output "thor_target_group_arn" {
  value = var.enable_compute ? module.ecs.target_group_arns["thor-api"] : null
}

output "thor_nlb_arn" {
  value = var.enable_compute ? module.ecs.nlb_arns["thor-api"] : null
}

output "thor_nlb_dns_name" {
  value = var.enable_compute ? module.ecs.nlb_dns_names["thor-api"] : null
}

output "api_gateway_invoke_url" {
  description = "Default execute-api invoke URL — no custom domain yet, and no Cognito/Lambda authorizer attached (open access, see modules/api_gateway/integration.tf)"
  value       = var.enable_compute ? module.api_gateway[0].invoke_url : null
}

output "thor_service_security_group_id" {
  value = var.enable_compute ? module.ecs.service_security_group_ids["thor-api"] : null
}

output "service_names" {
  value = module.ecs.service_names
}

output "task_execution_role_arns" {
  description = "Map of service name -> execution role ARN"
  value       = module.ecs.task_execution_role_arns
}

output "task_role_arns" {
  description = "Map of service name -> task role ARN — used to attach least-privilege DB/Bedrock policies per service without touching this module."
  value       = module.ecs.task_role_arns
}

output "frontend_bucket_name" {
  description = "S3 bucket the frontend deploy pipeline syncs to — set as thor-demo-frontend's S3_BUCKET_NAME GitHub Environment variable"
  value       = var.enable_frontend ? module.frontend[0].bucket_name : null
}

output "frontend_distribution_id" {
  description = "CloudFront distribution ID — set as thor-demo-frontend's CLOUDFRONT_DISTRIBUTION_ID GitHub Environment variable"
  value       = var.enable_frontend ? module.frontend[0].distribution_id : null
}

output "frontend_distribution_domain_name" {
  value = var.enable_frontend ? module.frontend[0].distribution_domain_name : null
}

output "acme_server_url" {
  description = "ACME directory this environment issues the TLS sidecar cert from — confirm this is the production endpoint, not Let's Encrypt staging, before relying on the cert being publicly trusted"
  value       = var.acme_server_url
}
