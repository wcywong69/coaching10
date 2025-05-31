data "aws_route53_zone" "sctp_zone" {
  name         = "sctp-sandbox.com"
  private_zone = false
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.wongs3_bucket.arn}/*",
    ]
  }
}