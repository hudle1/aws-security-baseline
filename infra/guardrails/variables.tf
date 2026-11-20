variable "account_id" {
  description = "12-digit ID of the sandbox AWS account. Used as allowed_account_ids so this stack can never apply to another account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be exactly 12 digits."
  }
}

variable "budget_email" {
  description = "Email address that receives budget alerts."
  type        = string
  sensitive   = true # keeps the address out of plan/apply output

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email must look like an email address."
  }
}

variable "budget_limit_usd" {
  description = "Monthly cost budget limit in USD."
  type        = number
  default     = 10

  validation {
    condition     = var.budget_limit_usd > 0
    error_message = "budget_limit_usd must be greater than 0."
  }
}

# Security contact for Security Hub Account.1. All three are sensitive: they are
# personal details, so they stay in guardrails.tfvars (gitignored) and out of plan output.
variable "security_contact_name" {
  description = "Name of the person AWS should contact about security issues for this account."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.security_contact_name) >= 1 && length(var.security_contact_name) <= 64
    error_message = "security_contact_name must be 1 to 64 characters."
  }
}

variable "security_contact_email" {
  description = "Email address that receives AWS security notices (abuse reports, compromised-credential warnings). Use a mailbox that is actually watched."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.security_contact_email))
    error_message = "security_contact_email must look like an email address."
  }
}

variable "security_contact_phone" {
  description = "Phone number for the security contact. Digits, spaces, parentheses, plus and hyphen only (AWS format), for example +1 702 555 0100."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9 ()+-]{1,25}$", var.security_contact_phone))
    error_message = "security_contact_phone may contain only digits, spaces, ( ) + - and be at most 25 characters."
  }
}
