# ClimbIt Production Environment

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "climbit-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "climbit-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ClimbIt"
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# VPC
module "vpc" {
  source = "../../modules/vpc"

  environment        = var.environment
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

# ECR Repositories
module "ecr" {
  source = "../../modules/ecr"

  environment      = var.environment
  repository_names = ["api", "jobs"]
}

# RDS Database
module "rds" {
  source = "../../modules/rds"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.vpc.rds_security_group_id
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  db_name           = "climbit"
}

# Secrets Manager
module "secrets" {
  source = "../../modules/secrets"

  environment = var.environment
  db_host     = module.rds.address
  db_port     = module.rds.port
  db_name     = module.rds.database_name
  db_username = module.rds.username
  db_password = module.rds.password
}

# ECS Cluster & Services
module "ecs" {
  source = "../../modules/ecs"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.vpc.alb_security_group_id
  ecs_security_group_id = module.vpc.ecs_security_group_id
  api_image             = "${module.ecr.repository_urls["api"]}:latest"
  jobs_image            = "${module.ecr.repository_urls["jobs"]}:latest"
  db_secret_arn         = module.secrets.db_secret_arn
  api_desired_count     = 1
}

# EventBridge Rule for Daily Weather Sync
resource "aws_cloudwatch_event_rule" "daily_weather_sync" {
  name                = "climbit-${var.environment}-daily-weather-sync"
  description         = "Trigger daily weather sync job"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "daily_weather_sync" {
  rule     = aws_cloudwatch_event_rule.daily_weather_sync.name
  arn      = module.ecs.cluster_id
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.ecs.jobs_task_definition_arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = module.vpc.private_subnet_ids
      security_groups  = [module.vpc.ecs_security_group_id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = "jobs"
        command = ["sync-weather", "--days", "14"]
      }
    ]
  })
}

# EventBridge Rule for Weekly Crag Sync
resource "aws_cloudwatch_event_rule" "weekly_crag_sync" {
  name                = "climbit-${var.environment}-weekly-crag-sync"
  description         = "Trigger weekly crag sync job"
  schedule_expression = "cron(0 4 ? * SUN *)" # 4 AM UTC every Sunday

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "weekly_crag_sync" {
  rule     = aws_cloudwatch_event_rule.weekly_crag_sync.name
  arn      = module.ecs.cluster_id
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.ecs.jobs_task_definition_arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = module.vpc.private_subnet_ids
      security_groups  = [module.vpc.ecs_security_group_id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = "jobs"
        command = ["sync-crags", "--max-areas", "500"]
      }
    ]
  })
}

# EventBridge Rule for Daily Safety Calculation
resource "aws_cloudwatch_event_rule" "daily_safety_calc" {
  name                = "climbit-${var.environment}-daily-safety-calc"
  description         = "Trigger daily safety status calculation"
  schedule_expression = "cron(30 6 * * ? *)" # 6:30 AM UTC daily (after weather sync)

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "daily_safety_calc" {
  rule     = aws_cloudwatch_event_rule.daily_safety_calc.name
  arn      = module.ecs.cluster_id
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.ecs.jobs_task_definition_arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = module.vpc.private_subnet_ids
      security_groups  = [module.vpc.ecs_security_group_id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = "jobs"
        command = ["calculate-safety"]
      }
    ]
  })
}

# IAM Role for EventBridge to run ECS tasks
resource "aws_iam_role" "eventbridge_ecs" {
  name = "climbit-${var.environment}-eventbridge-ecs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "climbit-${var.environment}-eventbridge-ecs-policy"
  role = aws_iam_role.eventbridge_ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          module.ecs.jobs_task_definition_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Outputs
output "api_url" {
  description = "API endpoint URL"
  value       = "http://${module.ecs.alb_dns_name}"
}

output "ecr_api_url" {
  description = "ECR repository URL for API"
  value       = module.ecr.repository_urls["api"]
}

output "ecr_jobs_url" {
  description = "ECR repository URL for Jobs"
  value       = module.ecr.repository_urls["jobs"]
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_api_service_name" {
  description = "ECS API service name"
  value       = module.ecs.api_service_name
}
