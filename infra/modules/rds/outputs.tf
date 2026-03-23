output "endpoint" {
  description = "RDS endpoint hostname (without port)"
  value       = aws_db_instance.main.address
}

output "port" {
  value = aws_db_instance.main.port
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "username" {
  value = aws_db_instance.main.username
}

output "instance_id" {
  value = aws_db_instance.main.identifier
}
