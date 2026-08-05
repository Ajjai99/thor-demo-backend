output "rest_api_id" {
  value = aws_api_gateway_rest_api.thor-apigw-restapi.id
}

output "vpc_link_id" {
  value = aws_api_gateway_vpc_link.thor-apigw-vpclink.id
}

output "stage_name" {
  value = aws_api_gateway_stage.thor-apigw-stage.stage_name
}

output "invoke_url" {
  description = "Default execute-api invoke URL — no custom domain yet"
  value       = aws_api_gateway_stage.thor-apigw-stage.invoke_url
}
