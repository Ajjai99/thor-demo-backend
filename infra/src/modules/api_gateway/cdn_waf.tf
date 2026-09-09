# CloudFront-scoped WAF ACLs are created via the global CloudFront API but always through the us-east-1 region
# specifically — this repo's every environment already runs in us-east-1 (root.hcl's account_map), so no second
# provider alias is needed here, same as modules/frontend's.
resource "aws_wafv2_web_acl" "api" {
  name        = "${local.cdn_name_prefix}-waf"
  description = "WAF for the thor-${var.environment} API CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS-managed core rule set — common exploits (XSS, path traversal, etc.). Worth knowing this group
  # includes SizeRestrictions_BODY, which blocks request bodies over 8KB: if this API ever takes larger
  # payloads, that specific rule needs excluding rather than the whole group being dropped.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.cdn_name_prefix}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # AWS-managed known-bad-inputs rule set — request patterns already known to be malicious.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.cdn_name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Basic protection — blocks a single IP sending more than var.cdn_waf_rate_limit requests in a rolling
  # 5-minute window. Separately tunable from the frontend's, since an API's normal call rate per
  # client looks nothing like a browser fetching a static bundle.
  rule {
    name     = "rate-limit-per-ip"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.cdn_waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.cdn_name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.cdn_name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${local.cdn_name_prefix}-waf"
  })

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
