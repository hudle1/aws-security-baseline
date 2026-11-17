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
