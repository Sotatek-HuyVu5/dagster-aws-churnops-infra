module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Allow kubectl from laptop
  cluster_endpoint_public_access = true

  # Required for IRSA
  enable_irsa = true

  # Terraform caller (CI/CD / developer) tự động được admin access sau khi tạo cluster
  enable_cluster_creator_admin_permissions = true

  # ─────────────────────────────────────────────
  # Node IAM Role — dùng chung cho cả 2 node groups
  # Module tự tạo role và attach các policy bắt buộc:
  #   - AmazonEKSWorkerNodePolicy
  #   - AmazonEKS_CNI_Policy
  #   - AmazonEC2ContainerRegistryReadOnly
  # ─────────────────────────────────────────────
  create_iam_role          = true
  iam_role_name            = "${var.project}-eks-node-role"
  iam_role_use_name_prefix = false
  iam_role_description     = "EKS managed node group role for ${var.project}"

  iam_role_additional_policies = {
    # Cho phép SSM Session Manager (optional nhưng hữu ích để debug nodes)
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # cluster_security_group_additional_rules: rule 443 nodes→API đã có sẵn trong module, không thêm để tránh duplicate

  # ─────────────────────────────────────────────
  # Node Security Group — thêm sg_eks_nodes_id vào nodes
  # FIX: sg_eks_nodes_id (từ networking module) được dùng bởi RDS/Redshift SG rules
  # → phải attach vào nodes thì RDS/Redshift mới accept traffic
  # ─────────────────────────────────────────────
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_groups = {

    # Node group 1 — t3.small On-Demand — dagster-webserver + dagster-daemon (stable services)
    webserver = {
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 1
      desired_size = 1

      subnet_ids             = var.private_subnet_ids
      vpc_security_group_ids = [var.sg_eks_nodes_id]

      labels = { workload = "webserver" }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }
    }

    # Node group 2 — t3.small Spot — Dagster run Job pods
    jobs = {
      instance_types = ["t3.small"]
      capacity_type  = "SPOT"

      min_size     = 1
      max_size     = 3
      desired_size = 1

      subnet_ids             = var.private_subnet_ids
      vpc_security_group_ids = [var.sg_eks_nodes_id]

      # Taint để chỉ Job pods (có toleration) mới schedule lên đây
      taints = [{
        key    = "workload"
        value  = "jobs"
        effect = "NO_SCHEDULE"
      }]

      labels = { workload = "jobs" }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }
    }
  }

  tags = { Name = "${var.project}-eks" }
}
