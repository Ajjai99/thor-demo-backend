# Publicly-trusted certificate for the ECS TLS sidecar (modules/ecs/tls_sidecar.tf). Let's Encrypt, not ACM: ACM
# never releases a certificate's private key, so it can't be installed on a container the way that sidecar needs.
# Let's Encrypt is a public CA where we hold the key ourselves — the only certificate type that's both publicly
# trusted (satisfies API Gateway's tls_config) and installable on a container we control.
#
# The acme provider's configuration (server_url) lives at the true root (infra/src/tls_certificate.tf) — a
# provider block can't be configured inside a child module. This module still needs required_providers for it
# below, same as every other module in this repo declares for aws; the configured instance is inherited
# implicitly from the root, no explicit provider-passing needed since there's only one (default, unaliased) acme
# provider instance in this whole configuration.
terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
  }
}

data "aws_region" "current" {}

# Must be public — Let's Encrypt's DNS-01 challenge queries the real public DNS system to see the TXT record it
# asks for; a private zone is only resolvable inside the VPC(s) it's attached to and is invisible to it entirely.
resource "aws_route53_zone" "acme" {
  name = var.root_domain
  tags = var.tags
}

# No email_address — optional on this resource, left unset deliberately. The tradeoff: no expiry/problem notices
# from Let's Encrypt if automated renewal ever silently breaks.
resource "acme_registration" "sidecar" {}

resource "acme_certificate" "sidecar" {
  account_key_pem = acme_registration.sidecar.account_key_pem
  common_name     = var.common_name

  dns_challenge {
    provider = "route53"

    config = {
      AWS_HOSTED_ZONE_ID = aws_route53_zone.acme.zone_id
      AWS_DEFAULT_REGION = data.aws_region.current.region
    }
  }
}
