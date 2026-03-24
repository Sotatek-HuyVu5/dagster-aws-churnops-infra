variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_ids" {
  description = "List of subnet IDs for RDS subnet group (needs ≥2 AZs)"
  type        = list(string)
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "postgres_version" {
  type    = string
  default = "15"
}

variable "db_name" {
  type    = string
  default = "dagster"
}

variable "username" {
  type    = string
  default = "dagster"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}
