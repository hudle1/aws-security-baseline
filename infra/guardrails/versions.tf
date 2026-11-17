terraform {
  # 1.9+ lets variables be referenced in more places (validation blocks, import ids).
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.0" means >= 6.0, < 7.0: minor/patch updates are allowed, a new
      # major (possible breaking changes) is not. .terraform.lock.hcl pins the
      # exact version + checksums on top of this.
      version = "~> 6.0"
    }
  }
}
