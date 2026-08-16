# Ingress lives in separate ingress_rule resources below, not inline — inline would create a dependency cycle across this for_each's own siblings.
resource "aws_security_group" "service" {
  for_each = local.active_services

  name        = "${local.name_prefix[each.key]}-service-sg"
  description = each.value.expose_publicly ? "ECS service ingress from within the VPC (NLB target, NLB has no SG), egress open (no NAT/IGW route today, so this only reaches the VPC + endpoints in practice)" : "ECS service ingress restricted to public-facing peer services only, egress open (no NAT/IGW route today, so this only reaches the VPC + endpoints in practice)"
  vpc_id      = var.vpc_id

  # 0.0.0.0/0, not var.vpc_cidr — no NAT/IGW route yet, so this only widens the boundary, not actual reachability.
  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix[each.key]}-service-sg"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Public-facing services: ingress from anywhere in the VPC — the NLB has no SG, so this is effectively "from the NLB."
resource "aws_vpc_security_group_ingress_rule" "public_from_vpc" {
  for_each = local.public_services

  security_group_id = aws_security_group.service[each.key].id
  description       = "From within the VPC"
  from_port         = each.value.container_port
  to_port           = each.value.container_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

# Internal services: ingress from each public peer's own SG, merged across every non-public × public pair.
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
  description                  = "From public-facing peer service: ${each.value.peer}"
  referenced_security_group_id = aws_security_group.service[each.value.peer].id
  from_port                    = local.active_services[each.value.service].container_port
  to_port                      = local.active_services[each.value.service].container_port
  ip_protocol                  = "tcp"

  tags = var.tags
}
