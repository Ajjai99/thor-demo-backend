output "ecr_repository_url" {
  description = "Populated regardless of enable_ingestion — a repo must exist before the flag can turn on"
  value       = aws_ecr_repository.ecr_ingestion.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.ecr_ingestion.arn
}

output "queue_arn" {
  value = var.enable_ingestion ? aws_sqs_queue.sqs_ingestion[0].arn : null
}

output "queue_url" {
  value = var.enable_ingestion ? aws_sqs_queue.sqs_ingestion[0].id : null
}

output "dlq_arn" {
  value = var.enable_ingestion ? aws_sqs_queue.sqs_ingestion_dlq[0].arn : null
}

output "state_machine_arn" {
  value = var.enable_ingestion ? aws_sfn_state_machine.sfn_ingestion[0].arn : null
}

output "create_manifest_function_arn" {
  value = var.enable_ingestion ? aws_lambda_function.manifest_lambda_function[0].arn : null
}

output "ingestion_task_definition_arn" {
  value = var.enable_ingestion ? aws_ecs_task_definition.ecs_ingestion_task_definition[0].arn : null
}
