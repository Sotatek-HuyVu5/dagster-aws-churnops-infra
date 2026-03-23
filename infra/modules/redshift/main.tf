resource "aws_redshiftserverless_namespace" "main" {
  namespace_name      = var.project
  admin_username      = var.admin_username
  admin_user_password = var.admin_password
  db_name             = "churnops"
  default_iam_role_arn = var.s3_role_arn
  iam_roles            = [var.s3_role_arn]

  tags = { Name = "${var.project}-redshift-ns" }
}

resource "aws_redshiftserverless_workgroup" "main" {
  namespace_name = aws_redshiftserverless_namespace.main.namespace_name
  workgroup_name = var.project
  base_capacity  = var.base_capacity

  subnet_ids         = var.db_subnet_ids
  security_group_ids = [var.sg_redshift_id]

  # Enhanced VPC routing — traffic stays within VPC
  enhanced_vpc_routing = true

  publicly_accessible = false

  tags = { Name = "${var.project}-redshift-wg" }
}
