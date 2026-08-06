# REQUEST-type, not TOKEN — API keys arrive as a plain header value, not a bearer token API Gateway needs to parse itself. Only exists when enable_authorizer is true, since the Lambda backing it may not exist yet in every environment.
resource "aws_api_gateway_authorizer" "api_key" {
  count = var.enable_authorizer ? 1 : 0

  name                             = "api-key-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.thor-apigw-restapi.id
  type                             = "REQUEST"
  authorizer_uri                   = var.authorizer_lambda_invoke_arn
  identity_source                  = "method.request.header.x-api-key"
  authorizer_result_ttl_in_seconds = 300
}

# API Gateway needs explicit permission to invoke the authorizer Lambda — this isn't implied by authorizer_uri alone.
resource "aws_lambda_permission" "authorizer_invoke" {
  count = var.enable_authorizer ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.thor-apigw-restapi.execution_arn}/authorizers/${aws_api_gateway_authorizer.api_key[0].id}"
}
