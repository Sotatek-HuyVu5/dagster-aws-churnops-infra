# Terraform Infrastructure Plan — ChurnOps (Production-grade, Cost-optimized)

> **Ngày lập**: 2026-03-23
> **Target**: AWS ap-southeast-1 · Single AZ
> **Compute**: EKS + EC2 Managed Node Groups · Không dùng ALB

---

## Quyết định kiến trúc

| Thành phần | Quyết định | Lý do |
|---|---|---|
| Orchestration | **EKS + EC2 nodes** | Chuẩn production, dễ scale |
| Node group 1 | **1× t3.micro** (daemon) | Workload nhẹ, chịu được taint |
| Node group 2 | **1× t3.small** (webserver + system) | Đủ RAM cho webserver + system pods |
| Load Balancer | **Không có ALB** | Dùng `kubectl port-forward` cho lab |
| IAM auth | **IRSA** (IAM Roles for Service Accounts) | Chuẩn EKS, least-privilege per pod |
| Redshift | **Serverless RPU 8** | Tự pause khi idle |
| PostgreSQL (Dagster metadata) | **RDS db.t3.micro** | Single AZ, 20GB gp2 |
| NAT Gateway | **1 NAT** (single AZ) | Không cần HA |
| SageMaker Training | **Managed Spot** | Tiết kiệm ~70% |

---

## 1. Kiến trúc tổng quan

```
                         Internet
                             │
                    ┌────────▼─────────┐
                    │  IGW             │
                    └────────┬─────────┘
                             │
              ┌──────────────▼────────────────┐
              │   Public Subnet (10.0.1.0/24)  │
              │   ┌──────────────────────┐     │
              │   │   NAT Gateway (1a)   │     │
              │   └──────────────────────┘     │
              └───────────────────────────────┘
                             │
              ┌──────────────▼────────────────────────────┐
              │   Private Subnet (10.0.11.0/24)            │
              │                                            │
              │  ┌─────────────────────────────────────┐  │
              │  │         EKS Cluster                  │  │
              │  │                                      │  │
              │  │  Node: t3.micro (1vCPU/1GB)          │  │
              │  │  ├─ dagster-daemon pod               │  │
              │  │  └─ kube-system pods                 │  │
              │  │                                      │  │
              │  │  Node: t3.small (2vCPU/2GB)          │  │
              │  │  ├─ dagster-webserver pod            │  │
              │  │  └─ kube-system pods (coredns...)    │  │
              │  └─────────────────────────────────────┘  │
              └────────────────────────────────────────────┘
                             │ IRSA
              ┌──────────────┼─────────────────────┐
              │              │                     │
              ▼              ▼                     ▼
      ┌───────────┐  ┌────────────────┐  ┌─────────────────┐
      │S3 Buckets │  │Redshift        │  │SageMaker Jobs   │
      │data/models│  │Serverless RPU8 │  │Spot ml.m5.xlarge│
      └───────────┘  └────────────────┘  └─────────────────┘

  Truy cập Dagster UI:
  kubectl port-forward svc/dagster-webserver 3000:3000
```

**Subnet layout:**
```
VPC: 10.0.0.0/16
├── 10.0.1.0/24   public-1a   (NAT Gateway)
├── 10.0.11.0/24  private-1a  (EKS nodes — tất cả workload)
├── 10.0.21.0/24  db-1a       (Redshift — bắt buộc ≥2 AZ)
└── 10.0.22.0/24  db-1b       (Redshift)
```

---

## 2. Cấu trúc thư mục Terraform

```
infra/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── terraform.tfvars.example
│
└── modules/
    ├── networking/       # VPC, subnets, SGs, NAT, S3 endpoint
    ├── s3/               # 2 S3 buckets
    ├── ecr/              # 2 ECR repos
    ├── iam/              # IAM roles (IRSA + SageMaker + Redshift + GitHub OIDC)
    ├── rds/              # RDS PostgreSQL (Dagster metadata DB)
    ├── redshift/         # Redshift Serverless
    ├── eks/              # EKS cluster + 2 node groups
    ├── ssm/              # SSM Parameters
    └── secrets/          # Secrets Manager
```

---

## 3. Chi tiết từng module

### 3.1 `networking`

| Resource | Tên | Config |
|---|---|---|
| `aws_vpc` | `churnops-vpc` | 10.0.0.0/16 |
| `aws_subnet` public×1 | `public-1a` | 10.0.1.0/24 — NAT GW |
| `aws_subnet` private×1 | `private-1a` | 10.0.11.0/24 — EKS nodes |
| `aws_subnet` db×2 | `db-1a`, `db-1b` | 10.0.21/22.0/24 — Redshift requirement |
| `aws_internet_gateway` | `churnops-igw` | |
| `aws_nat_gateway` | `churnops-nat` | 1 NAT ở public-1a |
| `aws_vpc_endpoint` | `s3-gateway` | Free, gắn vào cả 2 route tables |
| `aws_security_group` | `sg-eks-nodes` | Outbound all, inbound từ control plane + nodes |
| `aws_security_group` | `sg-redshift` | Inbound 5439 từ sg-eks-nodes + SageMaker |

> Bỏ `sg-alb` và `sg-ecs` so với plan cũ.

---

### 3.2 `s3` — không thay đổi

| Bucket | Config |
|---|---|
| `churnops-data-prod` | SSE-S3, block public, lifecycle expire 60 ngày |
| `churnops-models-prod` | SSE-S3, block public, versioning bật |

---

### 3.3 `ecr` — không thay đổi

2 repos: `churnops/dagster`, `churnops/sagemaker`, lifecycle giữ 5 images.

---

### 3.4 `iam`

EKS dùng **IRSA** (IAM Roles for Service Accounts) thay vì task role. Mỗi pod ServiceAccount map với 1 IAM Role riêng.

#### Role 1: `churnops-redshift-s3-role`
Trust: `redshift.amazonaws.com` — S3 read/write cho COPY/UNLOAD.

#### Role 2: `churnops-sagemaker-role`
Trust: `sagemaker.amazonaws.com` — SageMaker full + S3 access.

#### Role 3: `churnops-dagster-irsa-role` ← thay thế ECS task role
Trust: OIDC của EKS cluster + ServiceAccount `dagster/dagster-sa`

```hcl
# OIDC provider của EKS cluster
data "aws_iam_openid_connect_provider" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_role" "dagster_irsa" {
  name = "churnops-dagster-irsa"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:dagster:dagster-sa"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
```

Inline policy (same permissions as ECS task role cũ):
- S3 read/write cả 2 buckets
- SageMaker Create/Describe/Stop jobs
- `iam:PassRole` → chỉ trên `churnops-sagemaker-role`
- SSM GetParameter/PutParameter trên `/churnops/*`
- ECR pull
- CloudWatch Logs write
- Secrets Manager GetSecretValue trên `churnops/*`

#### Role 4: `churnops-github-actions-role`
Trust: GitHub OIDC — ECR push + EKS update (thêm `eks:DescribeCluster`).

---

### 3.5 `rds` ← module mới (Dagster metadata DB)

| Resource | Config |
|---|---|
| Engine | PostgreSQL 15.x |
| Instance | `db.t3.micro` (1vCPU / 1GB RAM) |
| Storage | 20 GB gp2, encrypted |
| Subnet group | `db-1a` + `db-1b` (reuse Redshift subnets) |
| Security group | `sg-rds`: inbound 5432 từ `sg-eks-nodes` |
| Multi-AZ | Không (lab) |
| Database name | `dagster` |
| Username | `dagster` |
| Password | Từ Secrets Manager `churnops/postgres_password` |
| Backup retention | 7 ngày |
| Skip final snapshot | `true` (lab) |

> Dagster dùng PostgreSQL này để lưu run history, asset materialization records, schedules.

---

### 3.6 `redshift` — không thay đổi

Redshift Serverless, base RPU 8, private subnets, enhanced VPC routing.

---

### 3.7 `eks` ← module mới thay `ecs`

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "churnops"
  cluster_version = "1.31"

  vpc_id                         = module.networking.vpc_id
  subnet_ids                     = [module.networking.private_subnet_1a_id]
  cluster_endpoint_public_access = true   # kubectl từ laptop

  # IRSA — bắt buộc cho Dagster pods
  enable_irsa = true

  eks_managed_node_groups = {

    # Node group 1: t3.micro — chạy dagster-daemon
    daemon = {
      instance_types = ["t3.micro"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      subnet_ids     = [module.networking.private_subnet_1a_id]

      # Taint để chỉ daemon pod schedule lên đây
      taints = [{
        key    = "workload"
        value  = "daemon"
        effect = "NO_SCHEDULE"
      }]

      labels = { workload = "daemon" }

      # Dùng Spot để tiết kiệm ~60%
      capacity_type = "SPOT"
    }

    # Node group 2: t3.small — chạy dagster-webserver + system pods
    webserver = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      subnet_ids     = [module.networking.private_subnet_1a_id]

      labels = { workload = "webserver" }

      capacity_type = "ON_DEMAND"   # Webserver cần stable
    }
  }
}
```

**Kubernetes resources** (deploy bằng Helm/kubectl sau khi EKS up):

```yaml
# ServiceAccount với IRSA annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dagster-sa
  namespace: dagster
  annotations:
    eks.amazonaws.com/role-arn: <churnops-dagster-irsa-role-arn>

---
# dagster-webserver Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dagster-webserver
  namespace: dagster
spec:
  replicas: 1
  template:
    spec:
      serviceAccountName: dagster-sa
      nodeSelector:
        workload: webserver
      containers:
      - name: dagster-webserver
        image: <ecr-uri>/churnops/dagster:<tag>
        args: ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000"]
        resources:
          requests: { cpu: "250m", memory: "512Mi" }
          limits:   { cpu: "500m", memory: "1Gi"   }
        ports:
        - containerPort: 3000
        envFrom:
        - secretRef:
            name: dagster-secrets   # K8s Secret từ Secrets Manager / SSM

---
# dagster-daemon Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dagster-daemon
  namespace: dagster
spec:
  replicas: 1
  template:
    spec:
      serviceAccountName: dagster-sa
      nodeSelector:
        workload: daemon
      tolerations:
      - key: "workload"
        value: "daemon"
        effect: "NoSchedule"
      containers:
      - name: dagster-daemon
        image: <ecr-uri>/churnops/dagster:<tag>
        args: ["dagster-daemon", "run"]
        resources:
          requests: { cpu: "100m", memory: "256Mi" }
          limits:   { cpu: "250m", memory: "512Mi" }
```

**Truy cập Dagster UI:**
```bash
kubectl port-forward -n dagster svc/dagster-webserver 3000:3000
# → http://localhost:3000
```

---

### 3.8 `ssm` — không thay đổi

10 parameters, thêm `/churnops/eks_cluster_name` + `/churnops/rds_endpoint`.

---

### 3.9 `secrets` — không thay đổi

`churnops/redshift_password` + `churnops/postgres_password`.

---

## 4. `versions.tf`

```hcl
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws        = { source = "hashicorp/aws",       version = "~> 5.80" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    helm       = { source = "hashicorp/helm",       version = "~> 2.16" }
  }
  backend "s3" {
    bucket         = "churnops-terraform-state"
    key            = "terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "churnops-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "churnops", ManagedBy = "terraform" }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
```

---

## 5. Thứ tự deploy

```bash
terraform init

# Phase 1 — Foundation
terraform apply \
  -target=module.networking \
  -target=module.ecr \
  -target=module.s3 \
  -target=module.secrets

# Phase 2 — IAM (cần sau networking vì OIDC cần cluster URL)
terraform apply -target=module.iam

# Phase 3 — Database
terraform apply -target=module.rds
terraform apply -target=module.redshift

# Phase 4 — EKS (lâu nhất, ~15 phút)
terraform apply -target=module.eks

# Phase 5 — SSM (cần output từ Redshift + EKS)
terraform apply -target=module.ssm

# Phase 6 — Final
terraform apply
```

---

## 6. Checklist sau deploy

- [ ] `aws eks update-kubeconfig --name churnops --region ap-southeast-1`
- [ ] Verify nodes: `kubectl get nodes`
- [ ] Build & push Docker images lên ECR
- [ ] Tạo namespace: `kubectl create namespace dagster`
- [ ] Tạo K8s Secret từ Secrets Manager / SSM outputs
- [ ] Apply Dagster manifests (webserver + daemon)
- [ ] Tạo Redshift schemas (`raw`, `staging`, `mart`, `predictions`)
- [ ] Test: `kubectl port-forward -n dagster svc/dagster-webserver 3000:3000`
- [ ] Trigger extraction job thủ công trong Dagster UI

---

## 7. Ước tính chi phí

### Per 4 giờ sử dụng

| Service | Đơn giá | 4h | Chi phí |
|---|---|---|---|
| EKS Control Plane | $0.10/h | ×4 | $0.40 |
| t3.micro Spot (daemon node) | ~$0.004/h | ×4 | $0.016 |
| t3.small On-Demand (webserver node) | $0.023/h | ×4 | $0.092 |
| NAT Gateway | $0.059/h | ×4 | $0.236 |
| Redshift Serverless (active ~2h) | $0.36 × 8 RPU | ×2 | $5.76 |
| S3, ECR, Secrets, SSM | — | — | ~$0.05 |
| SageMaker Spot (nếu chạy) | ~$0.08/h | ~1h | ~$0.08 |
| **Tổng** | | | **~$6.60** |

### Hàng tháng (24/7)

| Service | Chi phí |
|---|---|
| EKS Control Plane | $73 |
| t3.micro Spot | ~$3 |
| t3.small On-Demand | ~$17 |
| NAT Gateway | $43 |
| Redshift Serverless (~80 RPU-hours) | $23–46 |
| RDS db.t3.micro PostgreSQL | ~$13 |
| S3 + ECR + Secrets | $6 |
| SageMaker Spot (quarterly) | $3 |
| **Tổng** | **~$181–204/tháng** |

### So sánh các phương án

| Phương án | $/tháng | Ghi chú |
|---|---|---|
| ECS Fargate + ALB (plan gốc) | ~$111–131 | Tối ưu nhất về giá |
| **EKS + EC2 nodes + no ALB** | **~$168–191** | Plan hiện tại |
| EKS Fargate + no ALB | ~$165–185 | Không có Spot nodes |
| EKS + EC2 + ALB | ~$188–211 | Đắt nhất |

> **EKS tốn hơn ECS ~$60/tháng** chủ yếu do control plane ($73). Đổi lại được K8s ecosystem, IRSA fine-grained, dễ scale thêm services.

---

*Plan finalized: EKS + EC2 (t3.micro Spot + t3.small On-Demand) + no ALB.*
