data "aws_region" "current" {}

locals {
  # The trail ARN is BUILT from its name instead of read from aws_cloudtrail.main.arn.
  # Why: the key policy and bucket policy must name the trail, and the trail needs
  # both of them to exist first. Referencing the resource would be a dependency
  # cycle (trail -> policy -> trail). The name is known up front, so the ARN is too.
  trail_arn = "arn:aws:cloudtrail:${data.aws_region.current.region}:${var.account_id}:trail/${var.trail_name}"
}

locals {
  # What AWS Config sends as aws:SourceArn when it acts as the service principal:
  # always arn:aws:config:<region>:<account>:* for a delivery channel in that region
  # and account (AWS Config docs, "Permissions for the KMS Key for the AWS Config
  # Delivery Channel"). Used in the bucket policy and the Config key policy.
  config_source_arn = "arn:aws:config:${data.aws_region.current.region}:${var.account_id}:*"
}
