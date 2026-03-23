locals {
  prefix = "/${var.project}"
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "${local.prefix}/aws_region"
  type  = "String"
  value = var.aws_region
}

resource "aws_ssm_parameter" "data_bucket" {
  name  = "${local.prefix}/data_bucket_name"
  type  = "String"
  value = var.data_bucket_name
}

resource "aws_ssm_parameter" "models_bucket" {
  name  = "${local.prefix}/models_bucket_name"
  type  = "String"
  value = var.models_bucket_name
}

resource "aws_ssm_parameter" "dagster_ecr_repo" {
  name  = "${local.prefix}/dagster_ecr_repo_url"
  type  = "String"
  value = var.dagster_ecr_repo_url
}

resource "aws_ssm_parameter" "sagemaker_ecr_repo" {
  name  = "${local.prefix}/sagemaker_ecr_repo_url"
  type  = "String"
  value = var.sagemaker_ecr_repo_url
}

resource "aws_ssm_parameter" "redshift_workgroup" {
  name  = "${local.prefix}/redshift_workgroup_name"
  type  = "String"
  value = var.redshift_workgroup_name
}

resource "aws_ssm_parameter" "redshift_database" {
  name  = "${local.prefix}/redshift_database"
  type  = "String"
  value = var.redshift_database
}

resource "aws_ssm_parameter" "sagemaker_role_arn" {
  name  = "${local.prefix}/sagemaker_role_arn"
  type  = "String"
  value = var.sagemaker_role_arn
}

resource "aws_ssm_parameter" "dagster_irsa_role_arn" {
  name  = "${local.prefix}/dagster_irsa_role_arn"
  type  = "String"
  value = var.dagster_irsa_role_arn
}

resource "aws_ssm_parameter" "eks_cluster_name" {
  name  = "${local.prefix}/eks_cluster_name"
  type  = "String"
  value = var.eks_cluster_name
}

# RDS — Dagster metadata DB
resource "aws_ssm_parameter" "rds_endpoint" {
  name  = "${local.prefix}/rds_endpoint"
  type  = "String"
  value = var.rds_endpoint
}

resource "aws_ssm_parameter" "rds_db_name" {
  name  = "${local.prefix}/rds_db_name"
  type  = "String"
  value = var.rds_db_name
}

resource "aws_ssm_parameter" "rds_username" {
  name  = "${local.prefix}/rds_username"
  type  = "String"
  value = var.rds_username
}
