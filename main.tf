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
  database_subnets = ["10.1.1.0/24","10.1.2.0/24"]
  public_subnets  = ["10.1.3.0/24","10.1.4.0/24"]

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

resource "aws_security_group" "rds-sg" {
  name            = "rds-sg"
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
    description = "Allow database server connections on port 3306"
    from_port   = 3306
    to_port     = 3306
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
  vpc_security_group_ids = [aws_security_group.rds-sg.id]
}

resource "aws_instance" "LAMP-sample-instance" {
  ami = "ami-03e843d780a15a2d6" # custom AMI created manually
  instance_type = "t2.micro"

  subnet_id = module.vpc.public_subnets[0]
}

resource "aws_lb_target_group" "app-tg" {
  name = "app-lb-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = module.vpc.vpc_id
}

resource "aws_elb" "public-elb" {
  name = "public-internet-facing"
  subnets = module.vpc.public_subnets
  security_groups = [aws_security_group.public-facing-sg.id]

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
 
  tags = {
    Name = "Managed by Terraform"
  }
}

resource "aws_launch_template" "app-launch-template" {
 name = "app-launch-template"
 image_id = aws_instance.LAMP-sample-instance.ami
 instance_type = "t2.micro"
}

resource "aws_autoscaling_group" "app-asg" {
  name = "app-asg"
  desired_capacity = 2
  min_size = 2
  max_size = 8
  vpc_zone_identifier = module.vpc.public_subnets
  target_group_arns = [aws_lb_target_group.app-tg.arn]
  launch_template {
    id = aws_launch_template.app-launch-template.id
    version = "$Latest"
  }
}


resource "aws_autoscaling_policy" "app-scale-up" {
  name                   = "app-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app-asg.name
}

resource "aws_autoscaling_policy" "app-scale-down" {
  name                   = "app-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app-asg.name
}


resource "aws_cloudwatch_metric_alarm" "network-out-high" {
  alarm_name          = "network-out-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "NetworkOut"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "60"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app-asg.name
  }

  alarm_description = "This metric monitors average network out for the instance"
  alarm_actions = [aws_autoscaling_policy.app-scale-up.arn]
} 

resource "aws_cloudwatch_metric_alarm" "network-out-low" {
  alarm_name          = "network-out-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "NetworkOut"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "30"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app-asg.name
  }

  alarm_description = "This metric monitors average network out for the instance"
  alarm_actions = [aws_autoscaling_policy.app-scale-down.arn]
} 
