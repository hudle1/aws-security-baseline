# TFLint configuration, shared by both stacks (CI passes it with --config).
# TFLint is a linter: it catches mistakes `terraform validate` cannot, such as an
# unused variable, a deprecated syntax, or an AWS-specific error like an invalid
# instance type. It never calls AWS (deep_check stays off), so CI needs no credentials.

# Built-in "terraform" ruleset. The "recommended" preset enables the rules the
# TFLint authors consider safe for everyone: required version/provider pins,
# unused declarations, naming conventions, deprecated interpolation.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS ruleset. The version is PINNED, not "latest": a new release can add rules that
# turn a green build red without any change in this repo. Dependabot cannot update
# this line, so bump it by hand (see docs/operations/ci.md, "How to change it safely").
plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
