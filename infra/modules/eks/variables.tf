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

variable "sg_eks_nodes_id" {
  description = "Additional security group for EKS nodes (from networking module)"
  type        = string
}
