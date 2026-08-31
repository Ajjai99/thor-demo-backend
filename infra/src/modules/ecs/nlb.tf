locals {
  public_services = { for k, v in local.active_services : k => v if v.expose_via_nlb }

  # TLS re-encryption to the container (self-signed cert there, see tls-related env vars in
  # services.tf) only when a real cert is provided for the NLB's own listener — "" (default,
  # qa/prod today) keeps everything on plain TCP/HTTP, today's behavior.
  nlb_tls_enabled = var.nlb_certificate_arn != ""
}

# Regenerates whenever a ForceNew target-group attribute changes (port, protocol) — exactly when
# create_before_destroy needs a fresh, non-colliding name for the replacement target group.
resource "random_id" "tg_blue" {
  for_each    = local.public_services
  byte_length = 4

  keepers = {
    port     = each.value.container_port
    protocol = local.nlb_tls_enabled ? "TLS" : "TCP"
  }
}

resource "random_id" "tg_green" {
  for_each    = local.public_services
  byte_length = 4

  keepers = {
    port     = each.value.container_port
    protocol = local.nlb_tls_enabled ? "TLS" : "TCP"
  }
}

# Blue/primary target group. Green and the listener always exist too — toggling ROLLING/BLUE_GREEN shouldn't tear down the LB.
resource "aws_lb_target_group" "thor-nlb-tg-blue" {
  for_each = local.public_services

  # port/protocol/vpc_id/target_type all force replacement, and a fixed name would collide with
  # the still-existing old target group the moment Terraform tries to create the replacement (see
  # create_before_destroy below). AWS caps target group names at 32 chars total, so this appends
  # an 8-char suffix from random_id.tg_blue (which regenerates exactly when this needs a new one)
  # and truncates the descriptive part to fit — the untruncated name lives in the Name tag below.
  name        = substr("${local.name_prefix[each.key]}-blue-${random_id.tg_blue[each.key].hex}", 0, 32)
  port        = each.value.container_port
  protocol    = local.nlb_tls_enabled ? "TLS" : "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    # HTTPS is safe against a self-signed target cert — an NLB target group never validates it
    # (no chain-of-trust check against either TCP/TLS traffic or HTTP/HTTPS health checks), so an
    # HTTPS check here still gets a real HTTP response from the app instead of just a TCP handshake.
    protocol            = local.nlb_tls_enabled ? "HTTPS" : "HTTP"
    path                = each.value.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(var.tags, {
    Name = local.name_prefix[each.key]
  })

  # create_before_destroy makes a forced replacement (e.g. a future port/protocol change) create
  # the new target group before tearing down the old one — but the old one still won't delete on
  # its own: both aws_lb_listener resources below ignore_changes on default_action (so Terraform
  # doesn't fight ECS's own live blue/green traffic shifts), which means Terraform will never
  # repoint a listener at this new target group's ARN for you. Whenever a change here forces
  # replacement, temporarily drop `default_action` from both listeners' ignore_changes for that
  # one apply — that lets Terraform gracefully repoint the listener at the new target group before
  # destroying the old one — then restore ignore_changes afterward for normal blue/green operation.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tags, tags_all]
  }
}

resource "aws_lb_target_group" "thor-nlb-tg-green" {
  for_each = local.public_services

  # See the blue target group above for why this is a truncated name + random_id suffix.
  name        = substr("${local.name_prefix[each.key]}-green-${random_id.tg_green[each.key].hex}", 0, 32)
  port        = each.value.container_port
  protocol    = local.nlb_tls_enabled ? "TLS" : "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    # See the blue target group's health_check block above for why HTTPS is safe here.
    protocol            = local.nlb_tls_enabled ? "HTTPS" : "HTTP"
    path                = each.value.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix[each.key]}-green"
  })

  # See the blue target group above for what create_before_destroy does and doesn't solve here.
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [tags, tags_all]
  }
}

# SGs attach to an NLB only at creation, so wiring this in forces a replace of aws_lb.thor-nlb below.
resource "aws_security_group" "nlb" {
  for_each = local.public_services

  name        = "thor-nlb-${var.environment}-sg"
  description = "Thor NLB - ingress scoped to the listener ports only; target security groups reference this instead of allowing the whole VPC CIDR"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "thor-nlb-${var.environment}-sg"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
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

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_test_from_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.nlb[each.key].id
  description       = "Blue/green test listener, from within the VPC"
  from_port         = coalesce(each.value.nlb_test_listener_port, 8082)
  to_port           = coalesce(each.value.nlb_test_listener_port, 8082)
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.nlb[each.key].id
  description       = "To registered targets within the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
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
  protocol          = local.nlb_tls_enabled ? "TLS" : "TCP"
  certificate_arn   = local.nlb_tls_enabled ? var.nlb_certificate_arn : null
  ssl_policy        = local.nlb_tls_enabled ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.thor-nlb-tg-blue[each.key].arn
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [default_action, tags, tags_all]
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
  port              = coalesce(each.value.nlb_test_listener_port, 8082)
  protocol          = local.nlb_tls_enabled ? "TLS" : "TCP"
  certificate_arn   = local.nlb_tls_enabled ? var.nlb_certificate_arn : null
  ssl_policy        = local.nlb_tls_enabled ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null

  # green, not blue: this listener's job is validating the candidate task set (always the
  # alternate/green target group in this service's advanced_configuration, see services.tf)
  # before production traffic shifts.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.thor-nlb-tg-green[each.key].arn
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [default_action, tags, tags_all]
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

  name                 = "${local.name_prefix[each.key]}-bluegreen"
  assume_role_policy   = data.aws_iam_policy_document.ecs_service_assume.json
  permissions_boundary = var.iam_permissions_boundary_arn
  tags                 = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
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
