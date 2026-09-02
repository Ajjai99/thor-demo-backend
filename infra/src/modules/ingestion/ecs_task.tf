# The actual ingestion processing work — a one-shot Fargate task Step Functions runs on demand
# via ecs:runTask.sync2 (state_machine.tf), on this module's own dedicated cluster (isolated from
# modules/ecs's shared thor-<environment> cluster on purpose — separate blast radius/Container
# Insights view for ingestion). No aws_ecs_service here — this isn't a continuously-running
# service, so none of modules/ecs's service/load-balancer/deployment machinery applies.

resource "aws_ecs_cluster" "ecs_ingestion_cluster" {
  count = local.ingestion_active ? 1 : 0

  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-cluster"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_security_group" "ingestion_task_sg" {
  count = local.ingestion_active ? 1 : 0

  name        = "${local.name_prefix}-task-sg"
  description = "Ingestion ECS task - no inbound (invoked via the ECS API, not network traffic), egress open (no NAT/IGW route, so this only reaches the VPC + endpoints in practice)"
  vpc_id      = var.vpc_id

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-task-sg"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_cloudwatch_log_group" "ingestion_task_log_group" {
  count = local.ingestion_active ? 1 : 0

  name              = "/ecs/${var.environment}/ingestion"
  retention_in_days = var.log_retention_days
  tags              = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingestion_execution_role" {
  count = local.ingestion_active ? 1 : 0

  name                 = "${local.name_prefix}-execution"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task_assume.json
  permissions_boundary = var.iam_permissions_boundary_arn
  tags                 = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy_attachment" "ingestion_execution_policy_attachment" {
  count = local.ingestion_active ? 1 : 0

  role       = aws_iam_role.ingestion_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ingestion_task_role" {
  count = local.ingestion_active ? 1 : 0

  name                 = "${local.name_prefix}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task_assume.json
  permissions_boundary = var.iam_permissions_boundary_arn
  tags                 = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# The container's own runtime permissions — add more statements here as it needs more, not a new
# aws_iam_role_policy per permission.
data "aws_iam_policy_document" "ingestion_task_permissions_document" {
  count = local.ingestion_active ? 1 : 0

  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.s3_ingestion[0].arn, "${aws_s3_bucket.s3_ingestion[0].arn}/*"]
  }
}

resource "aws_iam_role_policy" "ingestion_task_permissions" {
  count = local.ingestion_active ? 1 : 0

  name   = "ingestion-task-permissions"
  role   = aws_iam_role.ingestion_task_role[0].id
  policy = data.aws_iam_policy_document.ingestion_task_permissions_document[0].json
}

locals {
  # Falls back to this module's own ECR repo at "latest" when unset — same fallback idiom as
  # modules/ecs/services.tf's resolved_image.
  resolved_ingestion_image = var.ingestion_container_image != "" ? var.ingestion_container_image : "${aws_ecr_repository.ecr_ingestion.repository_url}:latest"
}

resource "aws_ecs_task_definition" "ecs_ingestion_task_definition" {
  count = local.ingestion_active ? 1 : 0

  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ingestion_task_cpu
  memory                   = var.ingestion_task_memory
  execution_role_arn       = aws_iam_role.ingestion_execution_role[0].arn
  task_role_arn            = aws_iam_role.ingestion_task_role[0].arn

  container_definitions = jsonencode([
    {
      name      = "ingestion"
      image     = local.resolved_ingestion_image
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ingestion_task_log_group[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ingestion"
        }
      }
    }
  ])

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
