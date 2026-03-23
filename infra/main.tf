locals {
  name = "${var.project}-${var.environment}"
}

# ─────────────────────────────────────────────
# Phase 1 — Foundation
# ─────────────────────────────────────────────

module "networking" {
  source  = "./modules/networking"
  project = var.project
  vpc_cidr = var.vpc_cidr
}

module "s3" {
  source  = "./modules/s3"
  project = var.project
}

module "ecr" {
  source  = "./modules/ecr"
  project = var.project
}

module "secrets" {
  source             = "./modules/secrets"
  project            = var.project
  rds_password       = random_password.rds.result
  redshift_password  = random_password.redshift.result
}

# Random passwords — generated once, stored in Secrets Manager
resource "random_password" "rds" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "redshift" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ─────────────────────────────────────────────
# Phase 2 — IAM
# ─────────────────────────────────────────────

module "iam" {
  source = "./modules/iam"

  project             = var.project
  aws_region          = var.aws_region
  data_bucket_arn     = module.s3.data_bucket_arn
  models_bucket_arn   = module.s3.models_bucket_arn
  eks_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
}

# ─────────────────────────────────────────────
# Phase 3 — Databases
# ─────────────────────────────────────────────

module "rds" {
  source = "./modules/rds"

  project               = var.project
  db_subnet_ids         = module.networking.db_subnet_ids
  sg_eks_nodes_id       = module.networking.sg_eks_nodes_id
  vpc_id                = module.networking.vpc_id
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  postgres_version      = var.rds_postgres_version
  db_name               = var.rds_db_name
  username              = var.rds_username
  password              = random_password.rds.result
  skip_final_snapshot   = var.rds_skip_final_snapshot
}

module "redshift" {
  source = "./modules/redshift"

  project            = var.project
  db_subnet_ids      = module.networking.db_subnet_ids
  sg_redshift_id     = module.networking.sg_redshift_id
  base_capacity      = var.redshift_base_capacity
  admin_username     = var.redshift_admin_username
  admin_password     = random_password.redshift.result
  s3_role_arn        = module.iam.redshift_s3_role_arn
}

# ─────────────────────────────────────────────
# Phase 4 — EKS (lâu nhất ~15 phút)
# ─────────────────────────────────────────────

module "eks" {
  source = "./modules/eks"

  project            = var.project
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  sg_eks_nodes_id    = module.networking.sg_eks_nodes_id
}

# ─────────────────────────────────────────────
# Phase 5 — SSM (cần outputs từ tất cả modules)
# ─────────────────────────────────────────────

module "ssm" {
  source = "./modules/ssm"

  project                  = var.project
  aws_region               = var.aws_region
  data_bucket_name         = module.s3.data_bucket_name
  models_bucket_name       = module.s3.models_bucket_name
  dagster_ecr_repo_url     = module.ecr.dagster_repo_url
  sagemaker_ecr_repo_url   = module.ecr.sagemaker_repo_url
  redshift_workgroup_name  = module.redshift.workgroup_name
  redshift_database        = "churnops"
  sagemaker_role_arn       = module.iam.sagemaker_role_arn
  dagster_irsa_role_arn    = module.iam.dagster_irsa_role_arn
  eks_cluster_name         = module.eks.cluster_name
  rds_endpoint             = module.rds.endpoint
  rds_db_name              = var.rds_db_name
  rds_username             = var.rds_username
}
