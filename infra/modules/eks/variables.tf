variable "project" {
  type = string
}

variable "cluster_version" {
  type    = string
  default = "1.31"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "All private subnet IDs (>=2 AZs) for EKS cluster. Node groups pin to first subnet."
  type        = list(string)
}

variable "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions — granted EKS cluster admin access entry"
  type        = string
}
