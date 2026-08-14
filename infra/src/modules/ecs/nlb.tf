locals {
  public_services = { for k, v in local.active_services : k => v if v.expose_publicly }
}

# Blue/primary target group. Green and the listener always exist too — toggling ROLLING/BLUE_GREEN shouldn't tear down the LB.
resource "aws_lb_target_group" "thor-nlb-tg-blue" {
  for_each = local.public_services

  name        = local.name_prefix[each.key]
  port        = each.value.container_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = each.value.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = var.tags
}

resource "aws_lb_target_group" "thor-nlb-tg-green" {
  for_each = local.public_services

  name        = "${local.name_prefix[each.key]}-green"
  port        = each.value.container_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = each.value.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = var.tags
}

# Internal — reached via VPC Link from API Gateway, not directly from the internet.
resource "aws_lb" "thor-nlb" {
  for_each = local.public_services

  name               = local.name_prefix[each.key]
  load_balancer_type = "network"
  internal           = true
  subnets            = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix[each.key]}-nlb"
  })
}

# ECS modifies default_action during blue/green deploys — ignore it here to avoid fighting that.
resource "aws_lb_listener" "thor-nlb-listener" {
  for_each = local.public_services

  load_balancer_arn = aws_lb.thor-nlb[each.key].arn
  port              = each.value.nlb_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.thor-nlb-tg-blue[each.key].arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }

  tags = var.tags
}

# Lets test traffic hit the green revision before production traffic cuts over — AWS's optional blue/green
# "test traffic routing" step. Always created alongside the production listener (even for ROLLING services) so
# toggling deployment_strategy never tears down the LB; ECS only actually wires it in via advanced_configuration
# when deployment_strategy is BLUE_GREEN. Same ECS-managed default_action caveat as the production listener.
resource "aws_lb_listener" "thor-nlb-test-listener" {
  for_each = local.public_services

  load_balancer_arn = aws_lb.thor-nlb[each.key].arn
  port     = coalesce(each.value.nlb_test_listener_port, 8081)
  protocol = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.thor-nlb-tg-blue[each.key].arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }

  tags = var.tags
}

# Trusted by ecs.amazonaws.com (control plane), not ecs-tasks.amazonaws.com like iam.tf's roles.
data "aws_iam_policy_document" "ecs_service_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "blue_green" {
  for_each = local.public_services

  name               = "${local.name_prefix[each.key]}-bluegreen"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "blue_green_permissions" {
  for_each = local.public_services

  statement {
    actions = [
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "blue_green" {
  for_each = local.public_services

  name   = "blue-green-lb-access"
  role   = aws_iam_role.blue_green[each.key].id
  policy = data.aws_iam_policy_document.blue_green_permissions[each.key].json
}
