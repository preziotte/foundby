# Static hosting for foundby.dev: S3 + CloudFront + Route 53 + ACM, with CloudFront
# standard logging v2 on the apex distribution so the site's own logs feed foundby.
#
# Launch order (see ~/Sites/docs/launch-playbook.md): buy the domain, create the hosted
# zone by CLI (this file reads it as a data source), `terraform init && terraform plan`,
# start `apply`, then switch nameservers at the registrar while the apply waits on ACM.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

variable "domain_name" {
  description = "Canonical host, e.g. foundby.dev"
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "log_retention_days" {
  type    = number
  default = 400
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# ---------------------------------------------------------------------------
# Buckets

resource "aws_s3_bucket" "main" {
  bucket = var.domain_name
  tags   = { Name = var.domain_name }
}

resource "aws_s3_bucket" "www" {
  bucket = "www.${var.domain_name}"
  tags   = { Name = "www.${var.domain_name}" }
}

# Access logs. Log delivery prefixes the suffix path below with AWSLogs/<account-id>/CloudFront/,
# so the files live under s3://logs.<domain>/AWSLogs/<account-id>/CloudFront/cloudfront/apex/.
# That full prefix goes in foundby.json as edge.prefix.
resource "aws_s3_bucket" "logs" {
  bucket = "logs.${var.domain_name}"
  tags   = { Name = "logs.${var.domain_name}" }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AWSLogDeliveryWrite"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.logs.arn}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl"      = "bucket-owner-full-control"
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_website_configuration" "www" {
  bucket = aws_s3_bucket.www.id
  redirect_all_requests_to {
    host_name = var.domain_name
    protocol  = "https"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_public_access_block" "www" {
  bucket                  = aws_s3_bucket.www.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Sid       = "PublicReadForGetBucketObjects"
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::${var.domain_name}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.main]
}

# ---------------------------------------------------------------------------
# Certificate and DNS

resource "aws_acm_certificate" "cert" {
  provider                  = aws.us-east-1
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "zone" {
  name = var.domain_name
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# Search Console (domain property) and Bing Webmaster verification live here so a
# rebuild keeps them.
resource "aws_route53_record" "apex_txt" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["google-site-verification=Yo1SgCojQ4TmTcrYhezjRvNl4DRNOx6_HqbV5v4BSe4"]
}

resource "aws_route53_record" "bing_verification" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "b53d3799493c74fa4f0f370ed7f87173.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["verify.bing.com"]
}

# ---------------------------------------------------------------------------
# CloudFront

locals {
  delivery_name = replace(var.domain_name, ".", "-")
  distributions = {
    main = { origin = aws_s3_bucket_website_configuration.main.website_endpoint, alias = var.domain_name }
    www  = { origin = aws_s3_bucket_website_configuration.www.website_endpoint, alias = "www.${var.domain_name}" }
  }
}

resource "aws_cloudfront_distribution" "site" {
  for_each = local.distributions

  origin {
    domain_name = each.value.origin
    origin_id   = "S3-${each.value.alias}"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = each.key == "main" ? "index.html" : null
  aliases             = [each.value.alias]
  price_class         = "PriceClass_100"

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${each.value.alias}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Standard logging v2, apex only (www just 301s). Hourly partitions.
resource "aws_cloudwatch_log_delivery_source" "apex" {
  provider     = aws.us-east-1
  name         = "${local.delivery_name}-apex"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.site["main"].arn
}

resource "aws_cloudwatch_log_delivery_destination" "logs" {
  provider      = aws.us-east-1
  name          = "${local.delivery_name}-logs"
  output_format = "plain"
  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.logs.arn
  }
  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_cloudwatch_log_delivery" "apex" {
  provider                 = aws.us-east-1
  delivery_source_name     = aws_cloudwatch_log_delivery_source.apex.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.logs.arn
  s3_delivery_configuration {
    suffix_path                 = "cloudfront/apex/{yyyy}/{MM}/{dd}/{HH}"
    enable_hive_compatible_path = false
  }
  record_fields = [
    "timestamp", "c-ip", "cs-method", "cs(Host)", "cs-uri-stem", "sc-status", "cs(Referer)",
    "cs(User-Agent)", "cs-uri-query", "x-edge-result-type", "x-edge-response-result-type",
    "cs-protocol", "sc-bytes", "time-taken", "x-host-header",
  ]
}

resource "aws_route53_record" "alias" {
  for_each = local.distributions
  zone_id  = data.aws_route53_zone.zone.zone_id
  name     = each.value.alias
  type     = "A"
  alias {
    name                   = aws_cloudfront_distribution.site[each.key].domain_name
    zone_id                = aws_cloudfront_distribution.site[each.key].hosted_zone_id
    evaluate_target_health = false
  }
}

output "website_endpoint" {
  value = "https://${var.domain_name}"
}
output "s3_bucket_main" {
  value = aws_s3_bucket.main.bucket
}
output "cloudfront_distribution_main" {
  value = aws_cloudfront_distribution.site["main"].id
}
output "logs_prefix" {
  description = "edge.bucket and edge.prefix for foundby.json"
  value       = "s3://${aws_s3_bucket.logs.bucket}/AWSLogs/${data.aws_caller_identity.current.account_id}/CloudFront/cloudfront/apex/"
}
