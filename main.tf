resource "aws_s3_bucket" "wongs3_bucket" {
  bucket = "coaching10-wongs3.sctp-sandbox.com"

  tags = {
    "Name" = "Wong S3 Bucket in Coaching 10"
  }
}

resource "aws_s3_bucket_public_access_block" "enable_public_access" {
  bucket = aws_s3_bucket.wongs3_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket     = aws_s3_bucket.wongs3_bucket.id
  policy     = data.aws_iam_policy_document.bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.enable_public_access]
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.wongs3_bucket.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_policy" "s3_policy" {
  bucket = aws_s3_bucket.wongs3_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontAccessViaOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.wongs3_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cloudfront_distribution.arn
          }
        }
      }
    ]
  })
}

# resource "aws_cloudfront_origin_access_identity" "oai" {
#   comment = "OAI for CloudFront to access S3 bucket"
# }

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  depends_on = [aws_acm_certificate_validation.cert_validation]

  origin {
    domain_name = aws_s3_bucket.wongs3_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      #   origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
      origin_access_identity = "" # Leave this blank when using OAC
    }

    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id

  }

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "CloudFront Distribution for coaching10-wongs3"
  default_root_object = "index.html"

  aliases = ["coaching10-wongs3.sctp-sandbox.com"] # Replace with your actual domain name
  #aliases = [".sctp-sandbox.com"] # Replace with your actual domain name


  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS Managed-CachingOptimized
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "Wong CloudFront Distribution"
  }
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "CloudFront-OAC-to-S3"
  description                       = "Origin Access Control for S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_acm_certificate" "cert" {
    provider          = aws.us_east_1 # CloudFront requires ACM certs in us-east-1
    domain_name       = "coaching10-wongs3.sctp-sandbox.com"
    validation_method = "DNS"
    
    tags = {
        Name = "ACM cert for CloudFront"
    }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  
  zone_id = data.aws_route53_zone.sctp_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_route53_record" "alias" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "coaching10-wongs3"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate_validation" "cert_validation" {
    provider                = aws.us_east_1
    certificate_arn = aws_acm_certificate.cert.arn
    
    validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
    depends_on = [aws_route53_record.cert_validation]
}

data "aws_route53_zone" "zone" {
    name = "sctp-sandbox.com"
}

locals {
  website_root = "../coaching10_31May25_static_web"  # Change to your local folder
}

resource "aws_s3_object" "upload_files" {
  for_each = fileset(local.website_root, "**")

  bucket = aws_s3_bucket.wongs3_bucket.id
  key    = each.key
  source = "${local.website_root}/${each.key}"

  # Optional for content-type auto detection
  content_type = lookup(
    {
      html = "text/html"
      css  = "text/css"
      js   = "application/javascript"
      json = "application/json"
      png  = "image/png"
      jpg  = "image/jpeg"
      jpeg = "image/jpeg"
      svg  = "image/svg+xml"
    },
    # substr(each.key, length(each.key) - 2, 3),
    # "binary/octet-stream"
    regex("([^.]+)$", each.key)[0],
    "binary/octet-stream"
  )

  # Optional if you want the files to be publicly accessible (not needed if CloudFront handles access)
#   acl = "public-read"

  etag = filemd5("${local.website_root}/${each.key}")
}
