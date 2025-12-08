# ECR Module - Container Registry

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "repository_names" {
  description = "List of repository names to create"
  type        = list(string)
  default     = ["api", "jobs"]
}

locals {
  name_prefix = "climbit-${var.environment}"
}

# ECR Repositories
resource "aws_ecr_repository" "main" {
  for_each = toset(var.repository_names)

  name                 = "${local.name_prefix}-${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${local.name_prefix}-${each.value}"
    Environment = var.environment
  }
}

# Lifecycle policy to clean up old images
resource "aws_ecr_lifecycle_policy" "main" {
  for_each   = toset(var.repository_names)
  repository = aws_ecr_repository.main[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Outputs
output "repository_urls" {
  value = { for k, v in aws_ecr_repository.main : k => v.repository_url }
}

output "registry_id" {
  value = values(aws_ecr_repository.main)[0].registry_id
}
