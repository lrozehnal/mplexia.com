terraform {
  required_providers {
    aws = {}
  }
  backend "s3" {
    bucket = "ludek-terraform-states-buckets"
    key    = "mplexia.com/terraform.tfstate"
    region = "eu-west-1"
    use_lockfile   = true
    encrypt = true
  }
}

provider "aws" {
  alias  = "eu-west-1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
