resource "aws_secretsmanager_secret" "postgres_password" {
  name                    = "${var.project}/postgres_password"
  description             = "Dagster metadata DB (RDS PostgreSQL) password"
  recovery_window_in_days = 0  # immediate delete for lab

  tags = { Name = "${var.project}/postgres_password" }
}

resource "aws_secretsmanager_secret_version" "postgres_password" {
  secret_id     = aws_secretsmanager_secret.postgres_password.id
  secret_string = var.rds_password
}

resource "aws_secretsmanager_secret" "redshift_password" {
  name                    = "${var.project}/redshift_password"
  description             = "Redshift Serverless admin password"
  recovery_window_in_days = 0

  tags = { Name = "${var.project}/redshift_password" }
}

resource "aws_secretsmanager_secret_version" "redshift_password" {
  secret_id     = aws_secretsmanager_secret.redshift_password.id
  secret_string = var.redshift_password
}
