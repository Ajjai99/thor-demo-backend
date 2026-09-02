variable "environment" {
  type        = string
  description = "Environment name (dev, qa, prod)"
}

variable "account_id" {
  type        = string
  description = "AWS account ID this environment deploys into — root.hcl's account_map, supplied via var.account_id at the root. Used to build the ingestion bucket's globally-unique name without a live aws_caller_identity lookup, same convention as the permissions boundary ARN in infra/src/main.tf."
}

variable "aws_region" {
  type        = string
  description = "AWS region this environment deploys into — root.hcl's account_map, supplied via var.aws_region at the root. Used for the ingestion ECS task's awslogs-region log driver option without a live aws_region data source lookup."
}

variable "enable_ingestion" {
  type        = bool
  description = "Whether to create the ingestion pipeline (S3 -> SQS -> EventBridge Pipe -> CreateManifest Lambda -> Step Functions -> ECS ingestion task). The ECR repo is created regardless of this flag, so an image can be pushed before turning it on — everything else stays off until deliberately enabled."
}

variable "vpc_id" {
  type        = string
  description = "VPC the ingestion ECS task's security group is created in"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets the ingestion ECS task runs in — passed straight into the state machine's ecs:runTask.sync2 NetworkConfiguration"
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable ECS Container Insights on this module's own dedicated ingestion cluster — same root-level variable module.ecs uses for the shared cluster, threaded through separately since this cluster is isolated on purpose"
}

variable "iam_permissions_boundary_arn" {
  type        = string
  description = "ARN of the Console-created thor-<environment>-role-boundary policy (see docs/infra_pipeline_setup_guide.md) — required on this module's five IAM roles' (Pipe, CreateManifest, Step Functions, ingestion execution, ingestion task) permissions_boundary argument, or the deploy role's own iam:CreateRole grant rejects the call."
}

variable "tags" {
  type        = map(string)
  description = "Additional resource-specific tags"
  default     = {}
}

variable "max_retry_count" {
  type        = number
  description = "How many times the state machine will requeue a failed ingestion (CreateManifest or the ECS task failing) back onto the ingestion queue before giving up and sending it to the DLQ instead — this is the retry_count field carried in the message body, not SQS's own native redrive threshold (see sqs_max_receive_count)."
  default     = 3
}

variable "sqs_visibility_timeout_seconds" {
  type        = number
  description = "How long a message is hidden from other receivers once the EventBridge Pipe picks it up — must comfortably exceed create_manifest_timeout, since the Pipe holds the message until CreateManifest's synchronous invocation returns."
  default     = 60
}

variable "sqs_max_receive_count" {
  type        = number
  description = "SQS's own native redrive threshold to the DLQ — kept above max_retry_count so it only fires when the EventBridge Pipe itself repeatedly fails to deliver a message to CreateManifest, a different failure class than the state machine's own retry_count-driven requeue loop (a message the state machine re-sends via sqs:SendMessage gets a fresh ApproximateReceiveCount and would never trip this counter on its own)."
  default     = 5
}

variable "pipe_batch_size" {
  type        = number
  description = "How many SQS messages the EventBridge Pipe delivers to CreateManifest per invocation — the diagram's 'batch' label refers to this setting, not AWS Batch the service. Kept at 1 by default to keep CreateManifest's per-file logic simple."
  default     = 1
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention for this module's log groups (CreateManifest, the ingestion ECS task, the state machine)"
  default     = 30
}

variable "create_manifest_source_dir" {
  type        = string
  description = "Absolute path (via get_repo_root(), set in terragrunt.hcl) to CreateManifest's dotnet publish output — Terragrunt only copies infra/src, not backend/, so this can't be a relative path. data.archive_file zips it, it doesn't compile it, so dotnet publish must have already written here (see scripts/publish-lambda-functions.sh)."
}

variable "create_manifest_timeout" {
  type        = number
  description = "CreateManifest Lambda timeout in seconds — must stay under sqs_visibility_timeout_seconds, since the Pipe holds the SQS message for the full duration of this synchronous invocation"
  default     = 30
}

variable "create_manifest_memory_size" {
  type        = number
  description = "CreateManifest Lambda memory in MB"
  default     = 256
}

variable "ingestion_container_image" {
  type        = string
  description = "Pinned image URI for the ingestion ECS task; \"\" (default) falls back to this module's own ECR repo at :latest, same fallback idiom as modules/ecs/services.tf's resolved_image"
  default     = ""
}

variable "ingestion_task_cpu" {
  type        = number
  description = "Fargate CPU units for the ingestion task definition"
  default     = 512
}

variable "ingestion_task_memory" {
  type        = number
  description = "Fargate memory (MB) for the ingestion task definition"
  default     = 1024
}
