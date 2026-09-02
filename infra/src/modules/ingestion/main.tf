# Ingestion workflow: S3 -> SQS -> EventBridge Pipe -> CreateManifest (Lambda) -> Step Functions
# (runs the ingestion ECS task, then decides retry-vs-DLQ). See pipe.tf/lambda.tf/state_machine.tf.
#
# Diagram note (Untitled.png's "Ingestion Workflow" box): "EventBridge Pipe to Batch" does NOT
# mean AWS Batch — "batch" is the Pipe's batched SQS delivery setting. The Pipe's real target is
# CreateManifest, invoked directly and synchronously; AWS Batch plays no role in this workflow.

terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

locals {
  name_prefix      = "thor-${var.environment}-ingestion"
  ingestion_active = var.enable_ingestion
  bucket_name      = "thor-ingestion-${var.environment}-${var.account_id}"
}

resource "aws_s3_bucket" "s3_ingestion" {
  count = local.ingestion_active ? 1 : 0

  bucket = local.bucket_name
  tags   = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_s3_bucket_public_access_block" "s3_ingestion" {
  count = local.ingestion_active ? 1 : 0

  bucket                  = aws_s3_bucket.s3_ingestion[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "s3_ingestion" {
  count = local.ingestion_active ? 1 : 0

  bucket = aws_s3_bucket.s3_ingestion[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_ingestion" {
  count = local.ingestion_active ? 1 : 0

  bucket = aws_s3_bucket.s3_ingestion[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_sqs_queue" "sqs_ingestion_dlq" {
  count = local.ingestion_active ? 1 : 0

  name                      = "${local.name_prefix}-dlq"
  message_retention_seconds = 1209600 # 14 days — max, gives time to notice/investigate before loss
  tags                      = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "sqs_ingestion_dlq" {
  count = local.ingestion_active ? 1 : 0

  queue_url = aws_sqs_queue.sqs_ingestion_dlq[0].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.sqs_ingestion[0].arn]
  })
}

# maxReceiveCount is a backstop for a different failure class than the state machine's own
# retry_count field: it only fires if the EventBridge Pipe itself repeatedly fails to deliver a
# message to CreateManifest before Step Functions ever gets involved. Deliberately set above
# var.max_retry_count, since a message the state machine re-sends via sqs:SendMessage gets a
# fresh ApproximateReceiveCount and would never trip this counter on its own — see
# state_machine.tf for the retry_count-based decision that normally governs the requeue loop.
resource "aws_sqs_queue" "sqs_ingestion" {
  count = local.ingestion_active ? 1 : 0

  name                       = local.name_prefix
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sqs_ingestion_dlq[0].arn
    maxReceiveCount     = var.sqs_max_receive_count
  })
  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Required for S3 to be able to deliver bucket notifications to this queue at all — without this,
# aws_s3_bucket_notification silently gets zero events delivered, no error at apply time.
data "aws_iam_policy_document" "sqs_ingestion_queue_policy" {
  count = local.ingestion_active ? 1 : 0

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.sqs_ingestion[0].arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.s3_ingestion[0].arn]
    }
  }
}

resource "aws_sqs_queue_policy" "sqs_ingestion_policy" {
  count = local.ingestion_active ? 1 : 0

  queue_url = aws_sqs_queue.sqs_ingestion[0].id
  policy    = data.aws_iam_policy_document.sqs_ingestion_queue_policy[0].json
}

resource "aws_s3_bucket_notification" "s3_ingestion_event_notification" {
  count = local.ingestion_active ? 1 : 0

  bucket = aws_s3_bucket.s3_ingestion[0].id

  queue {
    queue_arn = aws_sqs_queue.sqs_ingestion[0].arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.sqs_ingestion_policy]
}
