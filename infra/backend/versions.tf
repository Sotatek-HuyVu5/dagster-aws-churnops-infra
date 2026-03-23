terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Backend này dùng local state (không cần remote)
  # vì nó chỉ chạy 1 lần để bootstrap
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "churnops"
      ManagedBy = "terraform"
    }
  }
}
