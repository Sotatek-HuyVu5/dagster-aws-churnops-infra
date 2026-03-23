output "dagster_repo_url" {
  value = aws_ecr_repository.dagster.repository_url
}

output "sagemaker_repo_url" {
  value = aws_ecr_repository.sagemaker.repository_url
}
