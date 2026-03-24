module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Standard support — tránh phí Extended ($0.60/cluster/hour)
  # Yêu cầu cluster đang chạy version trong standard support window (1.33+)
  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

  # Allow kubectl from laptop
  cluster_endpoint_public_access = true

  # Required for IRSA
  enable_irsa = true

  # Terraform caller (CI/CD / developer) tự động được admin access sau khi tạo cluster
  enable_cluster_creator_admin_permissions = true

  # Cluster IAM role (module tự tạo — bắt buộc, khác với node group role)
  iam_role_name            = "${var.project}-eks-cluster-role"
  iam_role_use_name_prefix = false

  # ─────────────────────────────────────────────
  # EKS Access Entry — GitHub Actions role
  # Cần để helm/kubectl chạy được từ CI/CD
  # ─────────────────────────────────────────────
  access_entries = {
    github_actions = {
      principal_arn = var.github_actions_role_arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = { Name = "${var.project}-eks" }
}

# ─────────────────────────────────────────────
# Fargate Pod Execution Role
# ─────────────────────────────────────────────

resource "aws_iam_role" "fargate_pod_execution" {
  name = "${var.project}-fargate-pod-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-fargate-pod-execution" }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# ─────────────────────────────────────────────
# Fargate Profile: dagster namespace
# Bắt toàn bộ pods trong namespace dagster (webserver, daemon, run jobs)
# ─────────────────────────────────────────────

resource "aws_eks_fargate_profile" "dagster" {
  cluster_name           = module.eks.cluster_name
  fargate_profile_name   = "${var.project}-dagster"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "dagster"
  }

  tags = { Name = "${var.project}-fargate-dagster" }
}

# ─────────────────────────────────────────────
# Fargate Profile: kube-system (CoreDNS)
# Fargate-only cluster bắt buộc phải chạy CoreDNS trên Fargate
# ─────────────────────────────────────────────

resource "aws_eks_fargate_profile" "kube_system" {
  cluster_name           = module.eks.cluster_name
  fargate_profile_name   = "${var.project}-kube-system"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
    labels    = { "k8s-app" = "kube-dns" }
  }

  tags = { Name = "${var.project}-fargate-kube-system" }
}
