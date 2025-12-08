# Secrets Module - AWS Secrets Manager

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_host" {
  description = "Database host"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 3306
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

locals {
  name_prefix = "climbit-${var.environment}"
}

# Database credentials secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.name_prefix}/db-credentials"
  description = "Database credentials for ClimbIt ${var.environment}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    host     = var.db_host
    port     = var.db_port
    database = var.db_name
    username = var.db_username
    password = var.db_password
    url      = "mysql+pymysql://${var.db_username}:${var.db_password}@${var.db_host}:${var.db_port}/${var.db_name}"
  })
}

# Outputs
output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db_credentials.name
}
