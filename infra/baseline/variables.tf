variable "account_id" {
  description = "12-digit ID of the sandbox AWS account. Used as allowed_account_ids and in policy ARNs, so this stack can never apply to another account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "trail_name" {
  description = "Name of the CloudTrail trail. Policies reference the trail ARN built from this name, so it is a variable, not a literal."
  type        = string
  default     = "baseline-trail"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$", var.trail_name))
    error_message = "trail_name must be 3-128 characters: letters, numbers, '.', '_' or '-', starting with a letter or number."
  }
}

variable "log_retention_days" {
  description = "Days before current log objects expire. Also the window in which log file validation can prove integrity, because digest files expire on the same schedule."
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 90
    error_message = "log_retention_days must be at least 90 (shorter retention can hide an intrusion that is found late)."
  }
}

variable "noncurrent_retention_days" {
  description = "Days an overwritten or deleted object version is kept before permanent deletion. This is the undo window for tampering."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_retention_days >= 1
    error_message = "noncurrent_retention_days must be at least 1."
  }
}

variable "alert_email" {
  description = "Email address that receives real-time security alerts (SNS subscription). Sensitive: it lives in baseline.tfvars (gitignored). The subscription stays 'pending' until the recipient clicks the confirmation link; Terraform cannot confirm it."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.alert_email))
    error_message = "alert_email must look like an email address (name@example.com)."
  }
}
