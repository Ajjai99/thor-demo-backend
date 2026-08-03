# Only one target NLB is supported per VPC Link on a REST API (AWS limit — target_arns takes a list but rejects more than one).
resource "aws_api_gateway_vpc_link" "this" {
  name        = "${var.service_name}-${var.environment}-vpclink"
  target_arns = [var.nlb_arn]
  tags        = var.tags
}

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.service_name}-${var.environment}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}
