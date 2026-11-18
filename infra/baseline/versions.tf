terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # Only used to generate the random suffix of the log bucket name (S3 names are
    # global, so the name must be unique and must not contain the account ID).
    # Official HashiCorp provider; pinned by .terraform.lock.hcl like aws.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
