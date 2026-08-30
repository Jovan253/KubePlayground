# KubePlayground — AWS infrastructure. Built in steps; see ROADMAP.md M9.
#   1 identity (this) · 2 ECR · 3 VPC · 4 EKS · 5 access
#
# State is local for now: the S3 bucket that will hold it doesn't exist yet, and
# can't hold the state that creates it. Migrated once step 2 lands. Until then
# terraform.tfstate is on this machine only (gitignored) and CI can't apply.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region

  # Project tag is how you find and delete everything this repo created — which
  # matters because the environment is meant to be destroyed between demos.
  default_tags {
    tags = {
      Project   = "KubePlayground"
      ManagedBy = "Terraform"
      Repo      = var.github_repo
    }
  }
}

data "aws_caller_identity" "current" {}
