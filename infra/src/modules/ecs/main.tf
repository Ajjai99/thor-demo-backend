data "aws_region" "current" {}

# Gates services.tf/nlb.tf/security_groups.tf/iam.tf — this cluster, the namespace below, and the ECR repos in ecr.tf stay unconditional since they don't need a container image to exist.
locals {
  active_services = var.enable_compute ? var.services : {}
}

resource "aws_ecs_cluster" "this" {
  name = "thor-${var.environment}"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name = "thor-${var.environment}-cluster"
  })

  # This AWS Organization runs Cloud Custodian, which auto-tags resources
  # with Owner/c7n-created-by/c7n-created-by-id/c7n-created-date shortly
  # after creation — an SCP explicitly blocks ecs:UntagResource so those
  # compliance tags can't be stripped back off. Terraform doesn't know
  # about them and would otherwise try to reconcile them away every apply,
  # which the SCP then denies. Ignoring tags/tags_all here stops Terraform
  # from fighting Custodian instead of trying to declare tags that are
  # dynamic per-resource values anyway.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# HTTP namespace, not Route53 private-DNS — Service Connect's Envoy sidecar resolves traffic itself and shares this namespace across every service so they can reach each other by name.
resource "aws_service_discovery_http_namespace" "this" {
  name        = "thor-${var.environment}.local"
  description = "Service Connect namespace for thor-${var.environment}"
  tags        = var.tags
}
