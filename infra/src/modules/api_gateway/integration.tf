# Catch-all proxy to the NLB listener. One integration, two routes (root + {proxy+}) — v2 lets routes share an integration.

resource "aws_apigatewayv2_integration" "proxy" {
  api_id = aws_apigatewayv2_api.thor-apigw-api.id

  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.thor-apigw-vpclink.id
  integration_uri        = var.nlb_listener_arn
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "proxy_root" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.thor-api-key[0].id : null
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.thor-api-key[0].id : null
}
