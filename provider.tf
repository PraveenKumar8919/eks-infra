terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }

  # Backend config is passed via -backend-config flags in CI (see .github/workflows/infra.yml)
  # For local use: terraform init -backend-config="bucket=<your-bucket>" -backend-config="key=eks-infra/state.tfstate" -backend-config="region=us-east-1"
  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}
