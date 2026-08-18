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

# SGs attach to an NLB only at creation, so wiring this in forces a replace of aws_lb.thor-nlb below.
resource "aws_security_group" "nlb" {
  for_each = local.public_services

  name        = "thor-nlb-${var.environment}-sg"
  description = "Thor NLB — ingress scoped to the listener ports only; target security groups reference this instead of allowing the whole VPC CIDR"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "thor-nlb-${var.environment}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.nlb[each.key].id
  description       = "Production listener, from within the VPC"
  from_port         = each.value.nlb_listener_port
  to_port           = each.value.nlb_listener_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_test_from_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.nlb[each.key].id
  description       = "Blue/green test listener, from within the VPC"
  from_port         = coalesce(each.value.nlb_test_listener_port, 8081)
  to_port           = coalesce(each.value.nlb_test_listener_port, 8081)
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.nlb[each.key].id
  description       = "To registered targets within the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

# Internal — reached via VPC Link from API Gateway, not directly from the internet. name is thor-nlb-<environment>,
# not the shared name_prefix — deliberately different, since there's only ever one shared public NLB, not one
# per service. Renaming an existing LB forces destroy+recreate (AWS names are immutable), applied deliberately.
resource "aws_lb" "thor-nlb" {
  for_each = local.public_services

  name               = "thor-nlb-${var.environment}"
  load_balancer_type = "network"
  internal           = true
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.nlb[each.key].id]

  tags = merge(var.tags, {
    Name = "thor-nlb-${var.environment}"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
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
  port              = coalesce(each.value.nlb_test_listener_port, 8081)
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
