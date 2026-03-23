# Networking
output "vpc_id" {
  value = module.networking.vpc_id
}

# EKS
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

# RDS
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = module.rds.endpoint
}

output "rds_port" {
  value = module.rds.port
}

# Redshift
output "redshift_workgroup_endpoint" {
  value = module.redshift.workgroup_endpoint
}

# S3
output "data_bucket_name" {
  value = module.s3.data_bucket_name
}

output "models_bucket_name" {
  value = module.s3.models_bucket_name
}

# ECR
output "dagster_ecr_repo_url" {
  value = module.ecr.dagster_repo_url
}

output "sagemaker_ecr_repo_url" {
  value = module.ecr.sagemaker_repo_url
}

# IAM
output "dagster_irsa_role_arn" {
  value = module.iam.dagster_irsa_role_arn
}
