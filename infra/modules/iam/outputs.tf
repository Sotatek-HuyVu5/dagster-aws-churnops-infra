output "redshift_s3_role_arn" {
  value = aws_iam_role.redshift_s3.arn
}

output "sagemaker_role_arn" {
  value = aws_iam_role.sagemaker.arn
}

output "dagster_irsa_role_arn" {
  value = aws_iam_role.dagster_irsa.arn
}
