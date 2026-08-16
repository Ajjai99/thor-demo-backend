data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# One execution role per service, scoped to only the secrets that service uses.
resource "aws_iam_role" "execution" {
  for_each = local.active_services

  name               = "${local.name_prefix[each.key]}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  for_each = local.active_services

  role       = aws_iam_role.execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets_access" {
  for_each = { for k, v in local.active_services : k => v if length(v.secrets) > 0 }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.aurora_secret_arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  for_each = data.aws_iam_policy_document.secrets_access

  name   = "secrets-access"
  role   = aws_iam_role.execution[each.key].id
  policy = each.value.json
}

# Task role — the app's own runtime permissions. X-Ray is the only baseline grant.
resource "aws_iam_role" "task" {
  for_each = local.active_services

  name               = "${local.name_prefix[each.key]}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_xray" {
  for_each = local.active_services

  role       = aws_iam_role.task[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# thor-api/task-api's own Aurora access via RDS Data API — add more statements here as the task role needs more permissions.
data "aws_iam_policy_document" "task_permissions" {
  for_each = { for k, v in local.active_services : k => v if contains(["thor-api", "task-api"], k) }

  statement {
    actions   = ["rds-data:ExecuteStatement"]
    resources = [var.aurora_cluster_arn]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.aurora_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_permissions" {
  for_each = data.aws_iam_policy_document.task_permissions

  name   = "task-permissions"
  role   = aws_iam_role.task[each.key].id
  policy = each.value.json
}
