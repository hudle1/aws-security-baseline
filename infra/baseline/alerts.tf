# Real-time alerts (decision Q-l): EventBridge rules -> one SNS topic -> email.
# Detect-only: a compromised admin can delete these rules or the topic (Tier 2: SCPs).
# All rules and the topic live in us-east-1; EventBridge rules are regional.
#
# Alert text carries only event names, resource names/IDs, times, severity and an
# event ID. NEVER secrets, and not the caller's identity or IP (docs/components/alerts.md).

resource "aws_sns_topic" "alerts" {
  name = "baseline-security-alerts"

  # Customer-managed key (decision Q-p). Encrypts messages at rest inside SNS only; it
  # does not protect the email path or the recipient's inbox.
  kms_master_key_id = aws_kms_key.alerts.arn
}

# Email subscription. Terraform creates it "pending"; it cannot confirm it. Nothing is
# delivered until the recipient clicks the link in the confirmation email.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # sensitive variable, never committed
}

# ---------------------------------------------------------------------------
# The rules. Each entry: an EventBridge pattern, the fields to pull out of the event
# (input_paths), and the readable text to send (input_template). <name> in the
# template is replaced by the matching input path. The template is one quoted string
# so SNS delivers plain text, not raw JSON.
# ---------------------------------------------------------------------------
locals {
  alert_rules = {
    cloudtrail-tamper = {
      description = "CloudTrail trail stopped, deleted or changed (threat model #1)"
      pattern = {
        source        = ["aws.cloudtrail"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["cloudtrail.amazonaws.com"]
          eventName   = ["StopLogging", "DeleteTrail", "UpdateTrail"]
        }
      }
      input_paths = {
        event    = "$.detail.eventName"
        resource = "$.detail.requestParameters.name"
        time     = "$.time"
        region   = "$.detail.awsRegion"
        id       = "$.detail.eventID"
      }
      input_template = "\"[SECURITY ALERT] CloudTrail <event> on trail <resource> at <time> (region <region>). CloudTrail event ID <id>. Check who did it with: aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventId,AttributeValue=<id>\""
    }

    kms-tamper = {
      description = "KMS key scheduled for deletion, disabled or key policy changed (threat models #4, #5). Any key in the account (decision Q-q)."
      pattern = {
        source        = ["aws.kms"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["kms.amazonaws.com"]
          eventName   = ["ScheduleKeyDeletion", "DisableKey", "PutKeyPolicy"]
        }
      }
      input_paths = {
        event    = "$.detail.eventName"
        resource = "$.detail.requestParameters.keyId"
        time     = "$.time"
        region   = "$.detail.awsRegion"
        id       = "$.detail.eventID"
      }
      input_template = "\"[SECURITY ALERT] KMS <event> on key <resource> at <time> (region <region>). CloudTrail event ID <id>. A scheduled deletion can be cancelled for 7 days: aws kms cancel-key-deletion --key-id <resource>\""
    }

    logbucket-tamper = {
      description = "Log bucket policy deleted/changed or versioning changed (threat models #2, #3)"
      pattern = {
        source        = ["aws.s3"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["s3.amazonaws.com"]
          eventName   = ["PutBucketPolicy", "DeleteBucketPolicy", "PutBucketVersioning"]
          requestParameters = {
            bucketName = [aws_s3_bucket.logs.id]
          }
        }
      }
      input_paths = {
        event    = "$.detail.eventName"
        resource = "$.detail.requestParameters.bucketName"
        time     = "$.time"
        region   = "$.detail.awsRegion"
        id       = "$.detail.eventID"
      }
      input_template = "\"[SECURITY ALERT] S3 <event> on log bucket <resource> at <time> (region <region>). CloudTrail event ID <id>.\""
    }

    config-tamper = {
      description = "AWS Config recorder stopped/deleted or delivery channel deleted (threat model #7)"
      pattern = {
        source        = ["aws.config"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["config.amazonaws.com"]
          eventName   = ["StopConfigurationRecorder", "DeleteDeliveryChannel", "DeleteConfigurationRecorder"]
        }
      }
      input_paths = {
        event  = "$.detail.eventName"
        time   = "$.time"
        region = "$.detail.awsRegion"
        id     = "$.detail.eventID"
      }
      input_template = "\"[SECURITY ALERT] AWS Config <event> at <time> (region <region>). CloudTrail event ID <id>.\""
    }

    guardduty-high = {
      description = "GuardDuty finding with severity 7 or higher (threat models #8, #9)"
      pattern = {
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail = {
          severity = [{ numeric = [">=", 7] }]
        }
      }
      input_paths = {
        type     = "$.detail.type"
        severity = "$.detail.severity"
        time     = "$.time"
        region   = "$.detail.region"
        id       = "$.detail.id"
      }
      input_template = "\"[SECURITY ALERT] GuardDuty finding <type>, severity <severity>, at <time> (region <region>). Finding ID <id>. Open it in the GuardDuty console.\""
    }

    access-analyzer-active = {
      description = "IAM Access Analyzer reports an ACTIVE external-access finding (threat model #21)"
      pattern = {
        source        = ["aws.access-analyzer"]
        "detail-type" = ["Access Analyzer Finding"]
        detail = {
          status = ["ACTIVE"]
        }
      }
      input_paths = {
        resource = "$.detail.resource"
        type     = "$.detail.resourceType"
        time     = "$.time"
        id       = "$.detail.id"
      }
      input_template = "\"[SECURITY ALERT] Access Analyzer: ACTIVE external access finding on <type> <resource> at <time>. Finding ID <id>.\""
    }
  }
}

resource "aws_cloudwatch_event_rule" "alerts" {
  for_each = local.alert_rules

  name          = "baseline-alert-${each.key}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)
  state         = "ENABLED"
}

resource "aws_cloudwatch_event_target" "alerts" {
  for_each = local.alert_rules

  rule = aws_cloudwatch_event_rule.alerts[each.key].name
  arn  = aws_sns_topic.alerts.arn

  # Rewrites the raw event JSON into one readable line of text for the email.
  input_transformer {
    input_paths    = each.value.input_paths
    input_template = each.value.input_template
  }

  # The topic policy must allow our rules to publish first, otherwise the target is
  # created but every delivery is silently denied.
  depends_on = [aws_sns_topic_policy.alerts]
}

# Who may publish to the topic: only EventBridge, and only on behalf of OUR six rules
# (aws:SourceArn). The KMS key policy can't carry this scoping (see kms-alerts.tf), so
# this policy is the one place that stops another account's rule from using the topic.
data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AllowOurEventBridgeRulesToPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for r in aws_cloudwatch_event_rule.alerts : r.arn]
    }
  }

  # Refuse non-TLS requests (same reasoning as the log bucket policy, statement 3).
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:Publish", "sns:Subscribe"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}
