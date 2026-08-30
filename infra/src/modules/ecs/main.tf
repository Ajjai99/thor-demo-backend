terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # For the short, non-colliding target group name suffixes in nlb.tf — needs no provider
    # configuration block of its own.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

data "aws_region" "current" {}

# Gates services/nlb/security_groups/iam.tf — the cluster, namespace, and ECR repos stay unconditional.
locals {
  active_services = var.enable_compute ? var.services : {}
}

resource "aws_ecs_cluster" "thor-ecs-cluster" {
  name = "thor-${var.environment}"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name = "thor-${var.environment}-cluster"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# HTTP namespace, not Route53 — Service Connect resolves traffic itself, shared so services reach each other by name.
resource "aws_service_discovery_http_namespace" "thor-sc-namespace" {
  name        = "thor-${var.environment}.local"
  description = "Service Connect namespace for thor-${var.environment}"
  tags        = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
