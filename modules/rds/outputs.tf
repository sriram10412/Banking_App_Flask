output "db_endpoint" {
  value     = aws_db_instance.main.address
  sensitive = true
}

output "db_identifier" { value = aws_db_instance.main.identifier }
output "db_secret_arn" { value = aws_secretsmanager_secret.db_credentials.arn }
