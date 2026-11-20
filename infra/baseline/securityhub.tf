# Security Hub (now branded "Security Hub CSPM" in the console and API errors; the
# Terraform resource names are unchanged). It runs the FSBP and CIS control checks,
# which are evaluated by AWS Config rules, so it depends on the Config recorder.

resource "aws_securityhub_account" "main" {
  # Default standards would silently turn on FSBP AND the old CIS v1.2.0. We enable
  # exactly the two we want, explicitly, below.
  enable_default_standards = false

  # One finding per control (SECURITY_CONTROL) instead of one per control per standard,
  # so a control that appears in both standards is a single finding to triage.
  control_finding_generator = "SECURITY_CONTROL"

  # Newly released controls in an enabled standard turn on automatically.
  auto_enable_controls = true

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]

  # Enabling a standard makes Security Hub create ~100 AWS Config rules one by one.
  # Measured 2026-11-18: about 20 minutes to READY. The provider default (3 minutes)
  # times out, leaves the resource tainted, and a re-apply would destroy and recreate
  # it. See docs/operations/troubleshooting.md #12.
  timeouts {
    create = "40m"
  }
}

# CIS v5.0.0: latest version Security Hub supports (describe-standards, 2026-11-18).
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.region}::standards/cis-aws-foundations-benchmark/v/5.0.0"
  depends_on    = [aws_securityhub_account.main]

  # Enabling a standard makes Security Hub create ~100 AWS Config rules one by one.
  # Measured 2026-11-18: about 20 minutes to READY. The provider default (3 minutes)
  # times out, leaves the resource tainted, and a re-apply would destroy and recreate
  # it. See docs/operations/troubleshooting.md #12.
  timeouts {
    create = "40m"
  }
}
