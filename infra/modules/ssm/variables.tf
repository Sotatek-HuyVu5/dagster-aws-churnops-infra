variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "data_bucket_name" {
  type = string
}

variable "models_bucket_name" {
  type = string
}

variable "dagster_ecr_repo_url" {
  type = string
}

variable "sagemaker_ecr_repo_url" {
  type = string
}

variable "redshift_workgroup_name" {
  type = string
}

variable "redshift_database" {
  type    = string
  default = "churnops"
}

variable "sagemaker_role_arn" {
  type = string
}

variable "dagster_irsa_role_arn" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "rds_endpoint" {
  description = "RDS PostgreSQL endpoint hostname"
  type        = string
}

variable "rds_db_name" {
  type = string
}

variable "rds_username" {
  type = string
}
