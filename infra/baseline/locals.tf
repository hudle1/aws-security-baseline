data "aws_region" "current" {}

locals {
  # The trail ARN is BUILT from its name instead of read from aws_cloudtrail.main.arn.
  # Why: the key policy and bucket policy must name the trail, and the trail needs
  # both of them to exist first. Referencing the resource would be a dependency
  # cycle (trail -> policy -> trail). The name is known up front, so the ARN is too.
  trail_arn = "arn:aws:cloudtrail:${data.aws_region.current.region}:${var.account_id}:trail/${var.trail_name}"
}
