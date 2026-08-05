terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Only one target NLB is supported per VPC Link on a REST API (AWS limit — target_arns takes a list but rejects more than one).
resource "aws_api_gateway_vpc_link" "thor-apigw-vpclink" {
  name        = "${var.service_name}-${var.environment}-vpclink"
  target_arns = [var.nlb_arn]
  tags        = var.tags
}

resource "aws_api_gateway_rest_api" "thor-apigw-restapi" {
  name = "${var.service_name}-${var.environment}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}
