variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "data_bucket_arn" {
  type = string
}

variable "models_bucket_arn" {
  type = string
}

variable "sagemaker_role_arn" {
  description = "Not used here — placeholder for cross-module reference"
  type        = string
  default     = ""
}

variable "eks_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

