# Bootstrap Module - Creates Terraform state infrastructure
#
# This module uses LOCAL state to create the S3 bucket and DynamoDB table
# that will store state for all other Terraform configurations.
#
# Run this ONCE before running any other Terraform:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # This module intentionally uses LOCAL state
  # because it creates the remote state infrastructure
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ClimbIt"
      ManagedBy = "Terraform-Bootstrap"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "climbit"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-terraform-locks"
  }
}

# IAM User for GitHub Actions CI/CD
resource "aws_iam_user" "github_actions" {
  name = "${var.project_name}-github-actions"

  tags = {
    Name = "${var.project_name}-github-actions"
  }
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

# IAM Policy for GitHub Actions
resource "aws_iam_user_policy" "github_actions" {
  name = "${var.project_name}-github-actions-policy"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Terraform State Access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
      # ECR Access
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:*:repository/${var.project_name}-*"
      },
      # ECS Access
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeClusters",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:ListServices",
          "ecs:ListClusters",
          "ecs:CreateCluster",
          "ecs:DeleteCluster",
          "ecs:CreateService",
          "ecs:DeleteService",
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:ResourceTag/Project" = "ClimbIt"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:ListServices",
          "ecs:ListClusters"
        ]
        Resource = "*"
      },
      # ECS Task Execution (needed for task definitions)
      {
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions"
        ]
        Resource = "*"
      },
      # IAM PassRole for ECS
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ecs-tasks.amazonaws.com",
              "events.amazonaws.com"
            ]
          }
        }
      },
      # Full Terraform permissions for infrastructure management
      # VPC
      {
        Effect = "Allow"
        Action = [
          "ec2:*Vpc*",
          "ec2:*Subnet*",
          "ec2:*RouteTable*",
          "ec2:*InternetGateway*",
          "ec2:*NatGateway*",
          "ec2:*SecurityGroup*",
          "ec2:*NetworkAcl*",
          "ec2:*Address*",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeAccountAttributes"
        ]
        Resource = "*"
      },
      # RDS
      {
        Effect = "Allow"
        Action = [
          "rds:*"
        ]
        Resource = "arn:aws:rds:${var.aws_region}:*:*:${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBSubnetGroups",
          "rds:DescribeDBParameterGroups",
          "rds:DescribeDBClusters",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:ModifyDBInstance",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      # Secrets Manager
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
          "logs:TagResource"
        ]
        Resource = "*"
      },
      # EventBridge
      {
        Effect = "Allow"
        Action = [
          "events:*"
        ]
        Resource = "arn:aws:events:${var.aws_region}:*:rule/${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "events:DescribeRule",
          "events:ListRules",
          "events:ListTargetsByRule",
          "events:PutRule",
          "events:PutTargets",
          "events:DeleteRule",
          "events:RemoveTargets"
        ]
        Resource = "*"
      },
      # IAM (for creating ECS task roles, etc.)
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::*:role/${var.project_name}-*"
      },
      # ELB (for ALB)
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Outputs
output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "github_actions_access_key_id" {
  description = "AWS Access Key ID for GitHub Actions (add to GitHub Secrets as AWS_ACCESS_KEY_ID)"
  value       = aws_iam_access_key.github_actions.id
}

output "github_actions_secret_access_key" {
  description = "AWS Secret Access Key for GitHub Actions (add to GitHub Secrets as AWS_SECRET_ACCESS_KEY)"
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}

output "github_secrets_instructions" {
  description = "Instructions for setting up GitHub Secrets"
  value       = <<-EOT

    Add these secrets to your GitHub repository:

    1. Go to: https://github.com/YOUR_USERNAME/climb-it/settings/secrets/actions
    2. Add the following secrets:

       AWS_ACCESS_KEY_ID     = ${aws_iam_access_key.github_actions.id}
       AWS_SECRET_ACCESS_KEY = (run 'terraform output -raw github_actions_secret_access_key')

  EOT
}
