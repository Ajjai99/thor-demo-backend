# Dropped enable_authorizer's count (e129272) but existing state still has these indexed at [0] —
# without these, they'd destroy-then-create in the same plan and cycle through the shared
# aws_apigatewayv2_api/stage dependency chain, same as module.lambda/module.secrets above.
moved {
  from = aws_apigatewayv2_authorizer.thor-api-key[0]
  to   = aws_apigatewayv2_authorizer.thor-api-key
}

moved {
  from = aws_lambda_permission.authorizer_invoke[0]
  to   = aws_lambda_permission.authorizer_invoke
}

# REQUEST-type authorizer for the x-api-key header. payload_format_version 1.0 keeps it compatible with Thor.Authorizer's IAM-policy response.
resource "aws_apigatewayv2_authorizer" "thor-api-key" {
  api_id                            = aws_apigatewayv2_api.thor-apigw-api.id
  name                              = "${var.service_name}-${var.environment}-authorizer"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = var.authorizer_lambda_invoke_arn
  authorizer_payload_format_version = "1.0"
  identity_sources                  = ["$request.header.x-api-key"]
  authorizer_result_ttl_in_seconds  = 300
}

# Grants API Gateway permission to invoke the authorizer Lambda.
resource "aws_lambda_permission" "authorizer_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.thor-apigw-api.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.thor-api-key.id}"
}
