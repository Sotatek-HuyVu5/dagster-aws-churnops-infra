variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "churnops"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# --- Networking ---

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

# --- EKS ---

variable "eks_cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.33"
}

# --- RDS ---

variable "rds_instance_class" {
  description = "RDS instance class for Dagster metadata DB"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS storage in GB"
  type        = number
  default     = 20
}

variable "rds_postgres_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15"
}

variable "rds_db_name" {
  description = "Initial database name"
  type        = string
  default     = "dagster"
}

variable "rds_username" {
  description = "Master username"
  type        = string
  default     = "dagster"
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy (set false for prod)"
  type        = bool
  default     = true
}

# --- Redshift ---

variable "redshift_base_capacity" {
  description = "Redshift Serverless base RPU capacity"
  type        = number
  default     = 8
}

variable "redshift_admin_username" {
  description = "Redshift admin username"
  type        = string
  default     = "admin"
}

variable "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions — granted EKS cluster admin access entry"
  type        = string
  default     = "arn:aws:iam::654654329682:role/github-assume-role"
}
