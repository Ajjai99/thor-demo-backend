terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  name_prefix = "thor-${var.environment}-aurora"

  # Falls back to a per-environment name — underscores, since unquoted Postgres identifiers can't use hyphens.
  database_name = var.database_name != "" ? var.database_name : "thor_${var.environment}_db"
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = local.name_prefix
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = local.name_prefix
  })
}

# No inline ingress — separate rule below, same dependency-cycle reasoning as ecs/security_groups.tf.
# name_prefix + create_before_destroy: a description change (or anything else forcing replacement) needs the new
# SG created — and the live Aurora cluster repointed at it — before the old one is destroyed. A fixed name would
# collide with the still-existing old SG the moment Terraform tries to create the replacement.
resource "aws_security_group" "aurora_security_group" {
  name_prefix = "${local.name_prefix}-sg-"
  description = "Aurora PostgreSQL - ingress per allowed_security_group_ids, egress scoped to the VPC"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  egress {
    description = "Within VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-sg"
  })
}

# One rule per entry in allowed_security_group_ids — map keys (not the IDs) are what for_each uses, see variables.tf.
resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each = var.allowed_security_group_ids

  security_group_id            = aws_security_group.aurora_security_group.id
  description                  = "PostgreSQL from ${each.key}"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.key}-ingress"
  })
}

# manage_master_user_password: AWS-rotated in Secrets Manager, never in state. enable_http_endpoint: RDS Data API, reachable from CI with no VPC access.
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier     = local.name_prefix
  engine                 = "aurora-postgresql"
  engine_version         = var.engine_version
  database_name          = local.database_name
  master_username        = var.master_username
  db_subnet_group_name   = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids = [aws_security_group.aurora_security_group.id]

  manage_master_user_password = true
  storage_encrypted           = true
  enable_http_endpoint        = true

  backup_retention_period   = var.backup_retention_days
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-final"

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = merge(var.tags, {
    Name = local.name_prefix
  })
}

# Serverless v2 still needs one instance resource — this is what actually runs; the cluster above is storage/control only.
resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier         = "${local.name_prefix}-instance"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora_cluster.engine
  engine_version     = aws_rds_cluster.aurora_cluster.engine_version

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-instance"
  })
}

# Second instance for Multi-AZ failover — kept as its own resource, not for_each, so it's purely additive.
resource "aws_rds_cluster_instance" "aurora_instance_2" {
  identifier         = "${local.name_prefix}-instance-2"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora_cluster.engine
  engine_version     = aws_rds_cluster.aurora_cluster.engine_version

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-instance-2"
  })
}
