# CloudFront in front of the HTTP API: the public hostname, TLS termination at the edge, and a WAF
# (cdn_waf.tf). Caching is deliberately off — this is the API's front door, not a content CDN.
#
# The API deliberately has no regional custom domain of its own. api.<env-domain> can point at
# CloudFront or at execute-api, not both, so a regional custom domain here would need a second
# hostname to serve as the origin and would buy nothing.
locals {
  cdn_name_prefix   = "${var.service_name}-${var.environment}-api-cdn"
  cdn_origin_id     = "apigw"
  use_custom_domain = var.domain_name != ""

  # The API's own default endpoint. Built from the api id rather than parsing the stage's
  # invoke_url, which carries a scheme and the stage path this origin splits across two arguments.
  cdn_origin_domain_name = "${aws_apigatewayv2_api.thor-apigw-api.id}.execute-api.${var.aws_region}.amazonaws.com"
}

# Looked up by name instead of pasting the well-known policy UUIDs — self-documenting, and a
# rename or a typo fails at plan time rather than silently attaching the wrong policy.
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "api" {
  enabled     = true
  comment     = local.cdn_name_prefix
  price_class = var.cdn_price_class
  web_acl_id  = aws_wafv2_web_acl.api.arn
  aliases     = local.use_custom_domain ? [var.domain_name] : []

  origin {
    domain_name = local.cdn_origin_domain_name
    origin_id   = local.cdn_origin_id
    # The stage isn't the API's $default, so its name is a real path segment on every invoke URL.
    origin_path = "/${aws_apigatewayv2_stage.thor-apigw-stage.name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.cdn_origin_id
    viewer_protocol_policy = "redirect-to-https"
    # Every method the routes expose (integration.tf) plus OPTIONS for preflight. cached_methods
    # stays GET/HEAD because CloudFront won't allow anything else, caching policy notwithstanding.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    # Caching is off, not tuned: this is a dynamic, per-caller-authorized API, so a shared edge
    # cache would hand one caller's response to the next.
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id

    # Forwards every header, cookie and query string EXCEPT Host. Both halves matter: x-api-key has
    # to survive the hop or the authorizer (authorizer.tf) rejects every request, and Host must NOT
    # be forwarded, since execute-api routes on its own hostname and 403s a request arriving with
    # the alias instead.
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Same mutually-exclusive pattern as modules/frontend: exactly one of the default certificate
  # and the acm_* fields is non-null at a time, never both.
  viewer_certificate {
    cloudfront_default_certificate = local.use_custom_domain ? null : true
    acm_certificate_arn            = local.use_custom_domain ? var.acm_certificate_arn : null
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.use_custom_domain ? "TLSv1.2_2021" : null
  }

  tags = merge(var.tags, {
    Name = local.cdn_name_prefix
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# CloudFront's hosted_zone_id (Z2FDTNDATAQYW2) is a fixed global constant, same as in modules/frontend.
resource "aws_route53_record" "cdn_alias_a" {
  count = local.use_custom_domain ? 1 : 0

  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.api.domain_name
    zone_id                = aws_cloudfront_distribution.api.hosted_zone_id
    evaluate_target_health = false
  }
}
