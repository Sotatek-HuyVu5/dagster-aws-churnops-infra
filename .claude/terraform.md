# Terraform — Claude Context

## Provider & Backend

- **Provider**: AWS `~> 5.80`, Kubernetes `~> 2.33`, Random `~> 3.6`
- **Required Terraform**: `>= 1.9`
- **State Backend**: S3 `churnops-terraform-state` + DynamoDB `churnops-terraform-locks` (ap-southeast-1)
- **Default tags** (auto-applied to all resources):
  ```hcl
  default_tags = { Project = "churnops", ManagedBy = "terraform" }
  ```

## Module Structure

Every module must have exactly these files:
```
modules/<name>/
├── main.tf        # Resources
├── variables.tf   # Input variables
└── outputs.tf     # Exported values
```

Do not add `provider.tf`, `versions.tf`, or other files inside child modules.

## Naming Convention

| Resource | Pattern |
|----------|---------|
| AWS resources | `churnops-<resource>` (e.g., `churnops-eks`, `churnops-rds`) |
| Terraform locals | snake_case |
| Terraform variables | snake_case |
| Module references | `module.<name>.<output>` |
| ECR repositories | `${var.project}/<service>` |
| SSM parameters | `/churnops/<key>` |
| Secrets Manager | `churnops/<name>` |

## Key Resource Decisions

### Networking
- Single NAT Gateway (cost saving for lab) — do NOT add second NAT without approval
- S3 Gateway VPC Endpoint enabled (free, reduces NAT costs)
- Redshift requires 3 DB subnets across 3 AZs (1a, 1b, 1c)
- EKS nodes use only private subnets (1a, 1b)

### EKS
- Cluster public endpoint enabled for `kubectl` from dev machines
- IRSA enabled — always use IRSA for pod-level AWS access, never instance profiles
- Node groups use `launch_template` for EBS configuration
- `cluster_creator_admin_permissions = true` — required for Terraform to manage cluster

### RDS (PostgreSQL)
- `skip_final_snapshot = true` — lab environment, do not change
- `deletion_protection = false` — intentional for easy teardown
- `performance_insights_enabled = true` (free 7-day tier)
- Password sourced from `aws_secretsmanager_secret_version`, not plain variables

### ECR
- `force_delete = true` on all repositories — allows destroy without manual image deletion
- Lifecycle policy: keep last 5 images, expire all others

### Secrets Manager
- `recovery_window_in_days = 0` — immediate deletion, no recovery period
- Passwords generated via `random_password` resource (Terraform-managed)

### IAM (IRSA)
- Dagster IRSA role trusts specific K8s ServiceAccount: `system:serviceaccount:dagster:dagster`
- Condition uses `StringEquals` on OIDC issuer sub claim
- `iam:PassRole` is scoped only to SageMaker role ARN

## Deploy Order

```
networking
    ├── s3
    ├── ecr
    └── secrets (random passwords)
          └── iam (needs EKS OIDC — from eks module)
                ├── rds
                ├── redshift
                └── eks
                      └── ssm (depends on all above outputs)
```

## Rules

1. **Do not use `count` or `for_each` on modules** unless explicitly needed — keep it simple
2. **All sensitive outputs** (passwords, keys) must use `sensitive = true`
3. **Never put passwords in `variables.tf` defaults** — always pull from Secrets Manager
4. **`terraform.tfvars` must never be committed** — use `terraform.tfvars.example` as template
5. **Run `terraform plan` before `apply`** — never `apply` blindly
6. **State is in S3** — always run `terraform init` after cloning or changing backend config
7. **Modules are not reusable across environments** yet — no `env` abstraction, single prod env
8. **Do not add `depends_on` unnecessarily** — use output references to create implicit deps
