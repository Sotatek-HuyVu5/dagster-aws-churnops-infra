variable "project" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "sg_redshift_id" {
  type = string
}

variable "base_capacity" {
  type    = number
  default = 8
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "s3_role_arn" {
  description = "IAM role ARN for Redshift S3 COPY/UNLOAD"
  type        = string
}
