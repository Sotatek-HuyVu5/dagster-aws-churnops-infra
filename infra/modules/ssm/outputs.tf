output "parameter_names" {
  description = "All SSM parameter names created"
  value = [
    aws_ssm_parameter.aws_region.name,
    aws_ssm_parameter.data_bucket.name,
    aws_ssm_parameter.models_bucket.name,
    aws_ssm_parameter.dagster_ecr_repo.name,
    aws_ssm_parameter.sagemaker_ecr_repo.name,
    aws_ssm_parameter.redshift_workgroup.name,
    aws_ssm_parameter.redshift_database.name,
    aws_ssm_parameter.sagemaker_role_arn.name,
    aws_ssm_parameter.dagster_irsa_role_arn.name,
    aws_ssm_parameter.eks_cluster_name.name,
    aws_ssm_parameter.rds_endpoint.name,
    aws_ssm_parameter.rds_db_name.name,
    aws_ssm_parameter.rds_username.name,
  ]
}
