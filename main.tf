terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region = "us-east-1"
}

resource "aws_eip" "nat" {
  count = 2

  vpc = true
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev-vpc"
  cidr = "10.1.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.1.1.0/24","10.1.2.0/24"]
  public_subnets  = ["10.1.3.0/24","10.1.4.0/24"]

  enable_nat_gateway  = true
  single_nat_gateway  = false
  reuse_nat_ips       = true
  external_nat_ip_ids = "${aws_eip.nat.*.id}"

  enable_vpn_gateway  = true


  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}
