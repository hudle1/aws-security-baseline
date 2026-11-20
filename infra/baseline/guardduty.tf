# GuardDuty: managed threat detection. Foundational sources (CloudTrail management
# events, VPC flow logs, DNS logs) are always analysed and need no setup. S3 Protection
# is enabled because CloudTrail data events are off (decision d). Every other paid
# protection plan is explicitly DISABLED (decision Q-o): a new detector can enable some
# of them by default, and an explicit DISABLED stops a billing feature switching on by accident.

resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3: us-east-1 only by decision Q-f (docs/design-decisions.md). All-region GuardDuty with alert forwarding is the first v1.1 item.
  enable = true

  # How often updated findings are re-published to EventBridge. 15 minutes is the
  # fastest value (default is 6 hours). Alert latency for repeat findings depends on it.
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

locals {
  guardduty_features = {
    S3_DATA_EVENTS         = "ENABLED"  # S3 Protection: object-level activity (decision d)
    EKS_AUDIT_LOGS         = "DISABLED" # no EKS clusters
    EBS_MALWARE_PROTECTION = "DISABLED" # no EC2 instances; billed per GB scanned
    RDS_LOGIN_EVENTS       = "DISABLED" # no RDS
    LAMBDA_NETWORK_LOGS    = "DISABLED" # no Lambda yet: enable when guardduty-triage (P2) deploys its Lambda
    RUNTIME_MONITORING     = "DISABLED" # agent-based EC2/ECS/EKS runtime protection; billed per vCPU, no workloads
    EKS_RUNTIME_MONITORING = "DISABLED" # older name of the same plan; set explicitly so it cannot be switched on by default
  }
}

resource "aws_guardduty_detector_feature" "main" {
  for_each = local.guardduty_features

  detector_id = aws_guardduty_detector.main.id
  name        = each.key
  status      = each.value
}
