# Ingress lives in separate ingress_rule resources below, not inline — inline would create a dependency cycle across this for_each's own siblings.
resource "aws_security_group" "service" {
  for_each = local.active_services

  name = "${local.name_prefix[each.key]}-service-sg"
  # description is ForceNew on aws_security_group and other resources reference this SG's id — changing this text
  # forces a destroy+recreate that can deadlock against those references (see security_groups.tf history). Left
  # matching what's already live in AWS; update only alongside a deliberate, planned replacement of this SG.
  description = each.value.expose_via_nlb ? "ECS service ingress from within the VPC (NLB target, NLB has no SG), egress open (no NAT/IGW route today, so this only reaches the VPC + endpoints in practice)" : "ECS service ingress restricted to public-facing peer services only, egress open (no NAT/IGW route today, so this only reaches the VPC + endpoints in practice)"
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

# Public-facing services: ingress from the NLB's own security group only — not the whole VPC CIDR.
resource "aws_vpc_security_group_ingress_rule" "public_from_vpc" {
  for_each = local.public_services

  security_group_id            = aws_security_group.service[each.key].id
  description                  = "From the NLB, to the TLS sidecar"
  from_port                    = local.sidecar_port[each.key]
  to_port                      = local.sidecar_port[each.key]
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nlb[each.key].id

  tags = var.tags
}

# Internal services: ingress from each public peer's own SG, merged across every non-public × public pair.
resource "aws_vpc_security_group_ingress_rule" "internal_from_public_peers" {
  for_each = merge([
    for svc_key, svc in local.active_services : svc.expose_via_nlb ? {} : {
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
