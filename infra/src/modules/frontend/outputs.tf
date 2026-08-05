output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "distribution_id" {
  value = aws_cloudfront_distribution.thor-fe-cdn.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.thor-fe-cdn.arn
}

output "distribution_domain_name" {
  value = aws_cloudfront_distribution.thor-fe-cdn.domain_name
}
