locals {
  # Every publicly-exposed service gets the sidecar — same set as nlb.tf's public_services, not a per-service opt-in.
  tls_sidecar_services = local.public_services

  # The app keeps listening on its own container_port unchanged (thor-api's is hardcoded in Program.cs/Dockerfile)
  # — the sidecar takes a new port instead, and becomes the one the NLB/API Gateway actually reach.
  sidecar_port = { for k, v in local.tls_sidecar_services : k => v.container_port + 1 }

  # Guarded the same way as the resource's own count — nginx[0] doesn't exist when tls_sidecar_services is empty,
  # and this local is evaluated unconditionally by Terraform regardless of whether anything ends up reading it.
  nginx_sidecar_image = length(local.tls_sidecar_services) > 0 ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${aws_ecr_pull_through_cache_rule.nginx[0].ecr_repository_prefix}/nginx/nginx:1.27-alpine" : null
}

data "aws_caller_identity" "current" {}

# network/main.tf gives private subnets no NAT Gateway route — only the ecr.api/ecr.dkr VPC endpoints — and
# public.ecr.aws (where the sidecar's nginx image lives) has no VPC endpoint of its own, so a direct pull from the
# task would fail. A pull-through cache repo proxies it: ECR fetches from public.ecr.aws over AWS's own backbone
# and serves it to the task through the existing private-ECR endpoints, no internet route needed from the task.
resource "aws_ecr_pull_through_cache_rule" "nginx" {
  count = length(local.tls_sidecar_services) > 0 ? 1 : 0

  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

# Publicly-trusted (Let's Encrypt via the ACME protocol — not AWS Certificate Manager, which never releases a
# private key), not self-signed or a private CA — API Gateway's HTTP API tls_config
# only accepts a certificate chained to a public CA, with no override (confirmed: the underlying AWS API's
# insecureSkipVerification field doesn't exist for HTTP API integrations, only REST APIs). The cert itself is
# requested at the root module level (infra/src/tls_certificate.tf) — provider configuration can't live inside a
# child module — and passed in here as plain strings to store.
resource "aws_secretsmanager_secret" "tls_sidecar" {
  for_each = local.tls_sidecar_services

  name = "${local.name_prefix[each.key]}-tls-sidecar-cert"
  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_secretsmanager_secret_version" "tls_sidecar" {
  for_each = local.tls_sidecar_services

  secret_id = aws_secretsmanager_secret.tls_sidecar[each.key].id
  secret_string = jsonencode({
    cert_pem  = var.tls_certificate_pem
    chain_pem = var.tls_certificate_chain_pem
    key_pem   = var.tls_private_key_pem
  })
}

# CreateRepository/BatchImportUpstreamImage are what let the execution role populate the pull-through cache repo
# on first pull — not covered by the AmazonECSTaskExecutionRolePolicy managed policy attached in iam.tf.
data "aws_iam_policy_document" "tls_sidecar_execution" {
  for_each = local.tls_sidecar_services

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.tls_sidecar[each.key].arn]
  }

  statement {
    actions   = ["ecr:CreateRepository", "ecr:BatchImportUpstreamImage"]
    resources = ["arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${aws_ecr_pull_through_cache_rule.nginx[0].ecr_repository_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "tls_sidecar_execution" {
  for_each = local.tls_sidecar_services

  name   = "tls-sidecar-execution-access"
  role   = aws_iam_role.execution[each.key].id
  policy = data.aws_iam_policy_document.tls_sidecar_execution[each.key].json
}
