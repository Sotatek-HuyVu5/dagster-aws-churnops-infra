# ─────────────────────────────────────────────
# Security Group — allow 5432 from EKS nodes
# ─────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.project}-sg-rds"
  description = "RDS PostgreSQL - Dagster metadata DB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.sg_eks_nodes_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-rds" }
}

# ─────────────────────────────────────────────
# DB Subnet Group — reuse db-1a and db-1b
# ─────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-rds-subnet-group"
  subnet_ids  = var.db_subnet_ids
  description = "Subnet group for Dagster metadata RDS"

  tags = { Name = "${var.project}-rds-subnet-group" }
}

# ─────────────────────────────────────────────
# DB Parameter Group
# ─────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  name   = "${var.project}-postgres15"
  family = "postgres${var.postgres_version}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = { Name = "${var.project}-postgres15" }
}

# ─────────────────────────────────────────────
# RDS Instance
# ─────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier = "${var.project}-dagster-db"

  # Engine
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = var.username
  password = var.password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Settings
  parameter_group_name    = aws_db_parameter_group.main.name
  multi_az                = false
  backup_retention_period = 7
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = false

  # Performance Insights — free tier (7 days)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = { Name = "${var.project}-dagster-db" }
}
