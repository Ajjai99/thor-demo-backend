terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_secretsmanager_secret" "thor-authorizer-salt" {
  name        = "thor-${var.environment}-authorizer-salt"
  description = "Salt for Thor.Authorizer's PBKDF2 API-key hashing. SecretString set out-of-band."

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
