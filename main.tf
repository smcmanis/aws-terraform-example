terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16.0"
    }
  }
}

provider "aws" {
  profile = "uts"
  region = "us-east-1"
}

locals {
  env = "dev"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.env}-vpc"
  cidr = "10.1.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.1.1.0/24","10.1.2.0/24"]
  public_subnets  = ["10.1.3.0/24","10.1.4.0/24"]
  database_subnets = ["10.1.5.0/24","10.1.6.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = local.env
  }
}

resource "aws_security_group" "public-facing-sg" {
  name            = "public-facing-sg"
  description     = "Managed by terraform"
  vpc_id          = module.vpc.vpc_id 

  egress {
    description     = "Outbound traffic to any destination"
    from_port       = 0
    to_port         = 65535
    protocol        = "all"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP requests on port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS requests on port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH via port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "sampledb" {
  allocated_storage    = 20
  max_allocated_storage = 1000
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  username             = "master"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  port                 = 3306
  db_subnet_group_name = "${local.env}-vpc"
  vpc_security_group_ids = [aws_security_group.public-facing-sg.id]
}