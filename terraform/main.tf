terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # S3 remote state backend — run bootstrap/s3-backend.sh first to create the bucket
  backend "s3" {
    bucket         = "helloworld-springboot-tfstate"
    key            = "ecs/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "helloworld-springboot-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region
}
