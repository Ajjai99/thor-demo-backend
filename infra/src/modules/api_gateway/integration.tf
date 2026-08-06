# Catch-all proxy — forwards every path/method through the VPC Link to the NLB, which forwards to thor. Locked behind the Lambda API-key authorizer only once enable_authorizer is true for this environment — Cognito user auth is still separate, unbuilt work.

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.thor-apigw-restapi.id
  parent_id   = aws_api_gateway_rest_api.thor-apigw-restapi.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.thor-apigw-restapi.id
  resource_id   = aws_api_gateway_rest_api.thor-apigw-restapi.root_resource_id
  http_method   = "ANY"
  authorization = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id = var.enable_authorizer ? aws_api_gateway_authorizer.api_key[0].id : null
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.thor-apigw-restapi.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id = var.enable_authorizer ? aws_api_gateway_authorizer.api_key[0].id : null

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy_root" {
  rest_api_id             = aws_api_gateway_rest_api.thor-apigw-restapi.id
  resource_id             = aws_api_gateway_rest_api.thor-apigw-restapi.root_resource_id
  http_method             = aws_api_gateway_method.proxy_root.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.thor-apigw-vpclink.id
  uri                     = "http://${var.nlb_dns_name}:${var.nlb_listener_port}/"
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.thor-apigw-restapi.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.thor-apigw-vpclink.id
  uri                     = "http://${var.nlb_dns_name}:${var.nlb_listener_port}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}
