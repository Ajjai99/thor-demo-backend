# Demo GET/POST routes, not a catch-all ANY — other methods get no route. One integration, four routes.

resource "aws_apigatewayv2_integration" "proxy" {
  api_id = aws_apigatewayv2_api.thor-apigw-api.id

  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.thor-apigw-vpclink.id
  integration_uri        = var.nlb_listener_arn
  payload_format_version = "1.0"

  # Plain HTTP end to end (var.tls_server_name == "") unless the NLB actually presents a real
  # cert — must agree with the NLB's own TLS state (modules/ecs/nlb.tf's nlb_tls_enabled), not
  # decided independently here.
  dynamic "tls_config" {
    for_each = var.tls_server_name != "" ? [1] : []
    content {
      server_name_to_verify = var.tls_server_name
    }
  }
}

resource "aws_apigatewayv2_route" "proxy_root_get" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.thor-api-key.id
}

resource "aws_apigatewayv2_route" "proxy_root_post" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.thor-api-key.id
}

resource "aws_apigatewayv2_route" "proxy_get" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.thor-api-key.id
}

resource "aws_apigatewayv2_route" "proxy_post" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "POST /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.thor-api-key.id
}
