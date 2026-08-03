# NLB has no security group of its own — publicly-exposed services (thor) allow ingress from anywhere in the VPC instead; internal services allow ingress only from those public services.
#
# Ingress is NOT inline here — it lives in the two aws_vpc_security_group_ingress_rule
# resources below instead. An inline ingress block that indexes into other
# instances of this same for_each resource (a non-public service's rule
# needing a public service's own SG id) stops Terraform from splitting
# per-instance dependencies: it conservatively treats every instance of
# aws_security_group.service as depending on every other instance, which is
# a real cycle once more than one service exists. A separate resource type
# depends ON the security group, not on itself, so the cycle can't happen.
resource "aws_security_group" "service" {
  for_each = local.active_services

  name        = "${local.name_prefix[each.key]}-service-sg"
  description = each.value.expose_publicly ? "ECS service ingress from within the VPC (NLB target, NLB has no SG), egress scoped to the VPC" : "ECS service ingress restricted to public-facing peer services only, egress scoped to the VPC"
  vpc_id      = var.vpc_id

  egress {
    description = "Within VPC only (endpoints, future DB security-group chaining)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix[each.key]}-service-sg"
  })
}

# Public-facing services (thor): ingress from anywhere in the VPC — the NLB
# has no security group of its own, so this is effectively "from the NLB."
resource "aws_vpc_security_group_ingress_rule" "public_from_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.service[each.key].id
  description        = "From within the VPC"
  from_port          = each.value.container_port
  to_port             = each.value.container_port
  ip_protocol        = "tcp"
  cidr_ipv4          = var.vpc_cidr

  tags = var.tags
}

# Internal-only services: ingress restricted to each public-facing peer
# service's own security group. Built as one map merged across every
# non-public service × every public peer, so this still holds if more than
# one service is ever expose_publicly = true, not just thor.
resource "aws_vpc_security_group_ingress_rule" "internal_from_public_peers" {
  for_each = merge([
    for svc_key, svc in local.active_services : svc.expose_publicly ? {} : {
      for peer_key in keys(local.public_services) : "${svc_key}-from-${peer_key}" => {
        service = svc_key
        peer    = peer_key
      }
    }
  ]...)

  security_group_id            = aws_security_group.service[each.value.service].id
  description                   = "From public-facing peer service: ${each.value.peer}"
  referenced_security_group_id = aws_security_group.service[each.value.peer].id
  from_port                     = local.active_services[each.value.service].container_port
  to_port                       = local.active_services[each.value.service].container_port
  ip_protocol                   = "tcp"

  tags = var.tags
}
