# ChurnOps Infrastructure — Claude Context

## Project Overview

**ChurnOps** is a customer churn prediction platform deployed on AWS. This repository contains all infrastructure-as-code (Terraform), Kubernetes manifests, Helm values, and CI/CD workflows for the production environment.

- **AWS Region**: ap-southeast-1 (Singapore)
- **AWS Account**: 654654329682
- **Environment**: prod
- **Terraform State**: S3 bucket `churnops-terraform-state`, DynamoDB lock `churnops-terraform-locks`

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| IaC | Terraform >= 1.9, AWS Provider ~> 5.80 |
| Orchestration | Dagster on EKS (Kubernetes 1.31) |
| Container Registry | ECR (`churnops/dagster`, `churnops/sagemaker`) |
| Compute | EKS managed node groups (EC2 t3.small) |
| Metadata DB | RDS PostgreSQL 15 (db.t3.micro) |
| Data Warehouse | Redshift Serverless (8 RPU) |
| Storage | S3 (data lake + ML models) |
| ML Training | Amazon SageMaker (job-based) |
| Auth | IAM IRSA (roles for K8s service accounts) |
| CI/CD | GitHub Actions + OIDC + Helm |
| Secrets | AWS Secrets Manager + SSM Parameter Store |
| Package Manager | Helm (official Dagster chart) |

---

## Folder Structure

```
.
├── CLAUDE.md                        # This file
├── .editorconfig                    # Editor settings (UTF-8, LF, 2-space indent)
├── .gitignore                       # Excludes terraform state, secrets, .env
│
├── .github/
│   └── workflows/
│       └── dagster-deploy.yml       # CI/CD: Helm deploy on push to master
│
├── docs/
│   ├── overview.md                  # Infrastructure planning (Vietnamese)
│   └── overview_plan.md             # Detailed architecture decisions (Vietnamese)
│
├── helm/
│   └── dagster/
│       └── values-prod.yaml         # Production Helm overrides for Dagster chart
│
├── infra/                           # Root Terraform module
│   ├── main.tf                      # Orchestrates all submodules
│   ├── variables.tf                 # Input variables
│   ├── versions.tf                  # Provider versions + S3 backend config
│   ├── outputs.tf                   # Exported values (VPC, EKS, RDS, etc.)
│   ├── terraform.tfvars.example     # Example vars (never commit .tfvars)
│   │
│   ├── backend/                     # Bootstrap: S3 + DynamoDB for Terraform state
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── versions.tf
│   │   └── outputs.tf
│   │
│   └── modules/
│       ├── networking/              # VPC, subnets, IGW, NAT, route tables, SGs
│       ├── s3/                      # Data lake + model storage buckets
│       ├── ecr/                     # Container registries
│       ├── iam/                     # IRSA roles, SageMaker role, Redshift role
│       ├── rds/                     # PostgreSQL for Dagster metadata
│       ├── redshift/                # Redshift Serverless data warehouse
│       ├── eks/                     # EKS cluster + managed node groups
│       ├── ssm/                     # SSM parameters (runtime config)
│       └── secrets/                 # Secrets Manager (passwords)
│
└── k8s/
    └── pre-install.sh               # Bootstrap K8s: namespaces, IRSA SA, secrets
```

---

## Architecture Overview

```
Internet
   │
   ▼
[IGW] → public subnet (10.0.1.0/24)
              │
            [NAT]
              │
   ┌──────────┴───────────┐
   ▼                       ▼
private-1a              private-1b
(EKS nodes)             (EKS nodes)
   │                       │
   └──────── EKS ──────────┘
                │
    ┌───────────┼────────────┐
    ▼           ▼            ▼
  Dagster    SageMaker    Dagster
  webserver  job pods     daemon
    │                       │
    └───── RDS PostgreSQL ──┘ (dagster metadata)
    └───── Redshift Serverless (data warehouse)
    └───── S3 (data lake, compute logs, models)
    └───── ECR (container images)
    └───── SSM / Secrets Manager (config & creds)
```

**EKS Node Groups:**
- `webserver`: t3.small On-Demand, label `workload=webserver` — runs Dagster webserver + daemon
- `jobs`: t3.small Spot, label `workload=jobs`, taint — runs Dagster pipeline job pods

**Networking CIDR:**
- VPC: `10.0.0.0/16`
- Public: `10.0.1.0/24`
- Private: `10.0.11.0/24`, `10.0.12.0/24`
- DB (Redshift needs 3 AZs): `10.0.21-23.0/24`

---

## Deployment Flow

### Infrastructure (Terraform)
```bash
# 1. Bootstrap state backend (run once)
cd infra/backend && terraform init && terraform apply

# 2. Deploy all infrastructure
cd infra && terraform init && terraform apply
```

**Module dependency order**: networking → (s3, ecr, secrets) → iam → (rds, redshift) → eks → ssm

### Application (CI/CD)
- **Trigger**: Push to `master` branch
- **Auth**: GitHub Actions OIDC → AWS role `github-assume-role`
- **Deploy**: `helm upgrade --install --rollback-on-failure`
- **Image tag format**: `YYYYMMDD-HHMMSS-<git-sha8>` (e.g., `20260323-103300-8cfba0b7`)

### Pre-install (first deploy only)
```bash
k8s/pre-install.sh   # Creates namespace, ServiceAccount (IRSA), K8s secrets
```

---

## Rules & Conventions

See subdirectory CLAUDE.md files for area-specific rules:
- [infra/CLAUDE.md](infra/CLAUDE.md) — Terraform rules
- [helm/CLAUDE.md](helm/CLAUDE.md) — Helm rules
- [k8s/CLAUDE.md](k8s/CLAUDE.md) — Kubernetes rules
- [.github/CLAUDE.md](.github/CLAUDE.md) — CI/CD rules

### General Rules

1. **Never commit secrets** — passwords, AWS keys, `.tfvars` files with real values
2. **Never commit `terraform.tfstate`** outside of `infra/backend/` (that one is intentional bootstrap)
3. **Always use `force_delete = true`** on ECR repositories
4. **Tag all AWS resources** — default tags `Project=churnops, ManagedBy=terraform` are auto-applied via provider
5. **Default region is ap-southeast-1** — never hardcode another region without discussion
6. **All modules follow** the pattern: `main.tf`, `variables.tf`, `outputs.tf` — no extra files unless necessary
7. **`skip_final_snapshot = true`** on RDS (lab environment) — do NOT change this without explicit instruction
8. **Redshift base capacity stays at 8 RPU** unless user explicitly requests scaling
