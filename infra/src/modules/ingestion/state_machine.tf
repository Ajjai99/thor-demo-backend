resource "aws_cloudwatch_log_group" "state_machine_log_group" {
  count = local.ingestion_active ? 1 : 0

  name              = "/aws/states/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

data "aws_iam_policy_document" "state_machine_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine_role" {
  count = local.ingestion_active ? 1 : 0

  name                 = "${local.name_prefix}-sf"
  assume_role_policy   = data.aws_iam_policy_document.state_machine_assume.json
  permissions_boundary = var.iam_permissions_boundary_arn
  tags                 = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# One policy for everything the state machine needs — add more statements here as it needs more,
# not a new aws_iam_role_policy per permission.
data "aws_iam_policy_document" "state_machine_permissions" {
  count = local.ingestion_active ? 1 : 0

  statement {
    actions   = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.ecs_ingestion_task_definition[0].arn]
  }

  # ecs:StopTask/DescribeTasks aren't resource-scopable to a specific task (the task's own ARN
  # doesn't exist until RunTask creates it) — Resource: "*" per AWS's own documented requirement.
  statement {
    actions   = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["*"]
  }

  # Step Functions passes both of the ingestion task's own roles to ECS when it starts the task
  # on the state machine's behalf.
  statement {
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ingestion_execution_role[0].arn,
      aws_iam_role.ingestion_task_role[0].arn,
    ]
  }

  # Real, easy-to-miss AWS requirement for the .sync/.sync2 ECS integration: Step Functions
  # auto-manages a hidden EventBridge rule (this fixed, AWS-owned name) to learn when the task
  # stops, and needs these three actions scoped to it to do so.
  statement {
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:aws:events:*:*:rule/StepFunctionsGetEventsForECSTaskRule"]
  }

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.sqs_ingestion[0].arn, aws_sqs_queue.sqs_ingestion_dlq[0].arn]
  }

  # Account-level log-delivery API Step Functions' own CloudWatch Logs integration requires —
  # not resource-scopable, same exception class as this repo's existing logs:DescribeLogGroups
  # grant elsewhere.
  statement {
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "state_machine_policy" {
  count = local.ingestion_active ? 1 : 0

  name   = "state-machine-permissions"
  role   = aws_iam_role.state_machine_role[0].id
  policy = data.aws_iam_policy_document.state_machine_permissions[0].json
}

# Runs the ingestion ECS task (only once CreateManifest reports success), then decides whether a
# failure should requeue to the ingestion queue or go to the DLQ — see main.tf's header comment
# for the overall flow this implements.
resource "aws_sfn_state_machine" "sfn_ingestion" {
  count = local.ingestion_active ? 1 : 0

  name     = local.name_prefix
  role_arn = aws_iam_role.state_machine_role[0].arn

  definition = jsonencode({
    Comment = "Ingestion workflow: run the ECS ingestion task on CreateManifest success, then requeue or DLQ on failure."
    StartAt = "EvaluateManifestOutcome"
    States = {
      EvaluateManifestOutcome = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.status"
            StringEquals = "success"
            Next         = "RunIngestionTask"
          }
        ]
        Default = "EvaluateRetryCount"
      }

      RunIngestionTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync2"
        Parameters = {
          Cluster        = aws_ecs_cluster.ecs_ingestion_cluster[0].name
          TaskDefinition = aws_ecs_task_definition.ecs_ingestion_task_definition[0].arn
          LaunchType     = "FARGATE"
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.private_subnet_ids
              SecurityGroups = [aws_security_group.ingestion_task_sg[0].id]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            "ContainerOverrides" = [
              {
                Name = "ingestion"
                Environment = [
                  { "Name" : "S3_BUCKET", "Value.$" : "$.bucket" },
                  { "Name" : "S3_KEY", "Value.$" : "$.key" },
                ]
              }
            ]
          }
        }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "EvaluateRetryCount"
          }
        ]
        Next = "WorkflowSucceeded"
      }

      EvaluateRetryCount = {
        Type = "Choice"
        Choices = [
          {
            Variable        = "$.retry_count"
            NumericLessThan = var.max_retry_count
            Next            = "RequeueToIngestionQueue"
          }
        ]
        Default = "SendToDeadLetterQueue"
      }

      RequeueToIngestionQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl        = aws_sqs_queue.sqs_ingestion[0].id
          "MessageBody.$" = "$"
        }
        End = true
      }

      SendToDeadLetterQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl        = aws_sqs_queue.sqs_ingestion_dlq[0].id
          "MessageBody.$" = "$"
        }
        End = true
      }

      WorkflowSucceeded = {
        Type = "Succeed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine_log_group[0].arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
