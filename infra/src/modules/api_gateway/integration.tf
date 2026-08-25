# Demo GET/POST routes, not a catch-all ANY — other methods get no route. One integration, four routes.

resource "aws_apigatewayv2_integration" "proxy" {
  api_id = aws_apigatewayv2_api.thor-apigw-api.id

  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.thor-apigw-vpclink.id
  integration_uri        = var.nlb_listener_arn
  payload_format_version = "1.0"

  # NLB stays TCP passthrough — this is what tells API Gateway to speak TLS to whatever's actually listening on
  # the other end (the sidecar, always present — see ecs module's tls_sidecar.tf). The sidecar's cert is issued by
  # Let's Encrypt (infra/src/tls_certificate.tf) specifically because it must chain to a public CA — HTTP API's
  # tls_config has no override for a private/self-signed cert (confirmed: insecureSkipVerification doesn't exist
  # for HTTP API integrations at all, only REST APIs).
  tls_config {
    server_name_to_verify = var.tls_server_name
  }
}

resource "aws_apigatewayv2_route" "proxy_root_get" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.thor-api-key[0].id : null
}

resource "aws_apigatewayv2_route" "proxy_root_post" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.thor-api-key[0].id : null
}

resource "aws_apigatewayv2_route" "proxy_get" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.thor-api-key[0].id : null
}

resource "aws_apigatewayv2_route" "proxy_post" {
  api_id    = aws_apigatewayv2_api.thor-apigw-api.id
  route_key = "POST /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"

  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.thor-api-key[0].id : null
}
