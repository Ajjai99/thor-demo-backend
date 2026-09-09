terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# VPC Link ENIs — egress only, nothing ever connects in.
resource "aws_security_group" "vpc_link" {
  name        = "${var.service_name}-${var.environment}-vpclink-sg"
  description = "API Gateway VPC Link ENIs, egress-only"
  vpc_id      = var.vpc_id

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.service_name}-${var.environment}-vpclink-sg"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_apigatewayv2_vpc_link" "thor-apigw-vpclink" {
  name               = "${var.service_name}-${var.environment}-vpclink"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = var.private_subnet_ids

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_apigatewayv2_api" "thor-apigw-api" {
  name          = "${var.service_name}-${var.environment}-api"
  protocol_type = "HTTP"

  # The frontend and the API sit on different hostnames (dev.<domain> vs api.dev.<domain>), which
  # browsers treat as cross-origin however closely related the names look — so preflight has to be
  # answered or every browser call fails before it reaches a route. Handled at the API level rather
  # than by an OPTIONS route on purpose: API Gateway answers preflight itself, without running the
  # authorizer, which an OPTIONS route would (and preflight requests carry no x-api-key to check).
  dynamic "cors_configuration" {
    for_each = length(var.cors_allow_origins) > 0 ? [1] : []
    content {
      allow_origins = var.cors_allow_origins
      allow_methods = var.cors_allow_methods
      allow_headers = var.cors_allow_headers
      max_age       = var.cors_max_age
    }
  }

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
