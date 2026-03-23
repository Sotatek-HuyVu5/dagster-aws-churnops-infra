output "postgres_secret_arn" {
  value = aws_secretsmanager_secret.postgres_password.arn
}

output "redshift_secret_arn" {
  value = aws_secretsmanager_secret.redshift_password.arn
}
