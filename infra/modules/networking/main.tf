# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# ─────────────────────────────────────────────
# Subnets
# ─────────────────────────────────────────────

resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)   # 10.0.1.0/24
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-1a" }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11)  # 10.0.11.0/24
  availability_zone = "${data.aws_region.current.name}a"

  tags = {
    Name                                          = "${var.project}-private-1a"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.project}"        = "owned"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 12)  # 10.0.12.0/24
  availability_zone = "${data.aws_region.current.name}b"

  tags = {
    Name                                          = "${var.project}-private-1b"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.project}"        = "owned"
  }
}

# db-1a, db-1b, db-1c — Redshift Serverless requires ≥3 subnets in 3 different AZs
resource "aws_subnet" "db_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 21)  # 10.0.21.0/24
  availability_zone = "${data.aws_region.current.name}a"

  tags = { Name = "${var.project}-db-1a" }
}

resource "aws_subnet" "db_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 22)  # 10.0.22.0/24
  availability_zone = "${data.aws_region.current.name}b"

  tags = { Name = "${var.project}-db-1b" }
}

resource "aws_subnet" "db_1c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 23)  # 10.0.23.0/24
  availability_zone = "${data.aws_region.current.name}c"

  tags = { Name = "${var.project}-db-1c" }
}

# ─────────────────────────────────────────────
# Internet Gateway + NAT Gateway
# ─────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1a.id
  tags          = { Name = "${var.project}-nat" }

  depends_on = [aws_internet_gateway.main]
}

# ─────────────────────────────────────────────
# Route Tables
# ─────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-rt-public" }
}

resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project}-rt-private" }
}

resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project}-rt-db" }
}

resource "aws_route_table_association" "db_1a" {
  subnet_id      = aws_subnet.db_1a.id
  route_table_id = aws_route_table.db.id
}

resource "aws_route_table_association" "db_1b" {
  subnet_id      = aws_subnet.db_1b.id
  route_table_id = aws_route_table.db.id
}

resource "aws_route_table_association" "db_1c" {
  subnet_id      = aws_subnet.db_1c.id
  route_table_id = aws_route_table.db.id
}

# ─────────────────────────────────────────────
# VPC Endpoint — S3 Gateway (free)
# ─────────────────────────────────────────────

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.db.id,
  ]

  tags = { Name = "${var.project}-s3-endpoint" }
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project}-sg-eks-nodes"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Node-to-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Control plane to nodes"
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-eks-nodes" }
}

resource "aws_security_group" "redshift" {
  name        = "${var.project}-sg-redshift"
  description = "Redshift Serverless"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redshift from EKS nodes"
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-redshift" }
}

# ─────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────

data "aws_region" "current" {}
