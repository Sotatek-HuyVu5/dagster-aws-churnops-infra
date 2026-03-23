variable "project" {
  type = string
}

variable "rds_password" {
  type      = string
  sensitive = true
}

variable "redshift_password" {
  type      = string
  sensitive = true
}
