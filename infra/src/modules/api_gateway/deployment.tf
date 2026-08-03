resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Forces a new deployment whenever the resources/methods/integrations actually change — a deployment otherwise has no config of its own to detect drift from.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy_root.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy_root.id,
      aws_api_gateway_integration.proxy.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.proxy_root, aws_api_gateway_integration.proxy]
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.environment

  tags = var.tags
}
