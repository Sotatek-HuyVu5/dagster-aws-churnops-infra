# Kubernetes — Claude Context

## Cluster

- **Cluster name**: `churnops`
- **Kubernetes version**: 1.31
- **Region**: ap-southeast-1
- **Access**: Public endpoint (for `kubectl` from dev machines)
- **Namespace**: `dagster` (all Dagster resources)

## pre-install.sh

This script must be run **once before the first Helm deployment**. It sets up prerequisites that Helm expects to already exist.

### What it does (in order)
1. Reads Terraform outputs: cluster name, IRSA role ARN, RDS endpoint, ECR URI, S3 bucket
2. Updates local `kubeconfig` via `aws eks update-kubeconfig`
3. Creates `dagster` namespace
4. Creates `dagster` ServiceAccount with IRSA annotation
5. Fetches RDS password from Secrets Manager (`churnops/postgres_password`)
6. Creates K8s Secret `dagster-postgresql-secret` (PostgreSQL connection password)
7. Creates K8s Secret `dagster-secrets` (environment variables for Dagster pods)
8. Adds Dagster Helm repo

### IRSA Annotation
```yaml
annotations:
  eks.amazonaws.com/role-arn: <dagster-irsa-role-arn>
```
The role ARN comes from Terraform output `dagster_irsa_role_arn`.

### K8s Secrets Created

**`dagster-postgresql-secret`**
```
postgresql-password: <rds-password-from-secrets-manager>
```

**`dagster-secrets`**
```
DAGSTER_PG_HOST:      <rds-endpoint>
DAGSTER_PG_DB:        dagster
DAGSTER_PG_USER:      dagster
DAGSTER_S3_BUCKET:    churnops-data-prod
DAGSTER_ECR_URI:      <ecr-dagster-repo-url>
AWS_REGION:           ap-southeast-1
```

## Node Groups & Scheduling

| Node Group | Instance | Capacity | Label | Taint |
|-----------|---------|---------|-------|-------|
| webserver | t3.small | 1 On-Demand | `workload=webserver` | none |
| jobs | t3.small | 1-3 Spot | `workload=jobs` | `workload=jobs:NoSchedule` |

- Dagster webserver and daemon pods → `workload=webserver` nodes
- Dagster run (pipeline job) pods → `workload=jobs` nodes (spot)
- Job pods must include matching toleration for the taint

## Rules

1. **Run `pre-install.sh` before first Helm deploy** — Helm will fail without the ServiceAccount and secrets
2. **Do not manually create resources that Terraform manages** — EKS cluster, node groups, IAM roles
3. **Never use `kubectl apply -f` for Dagster resources** — everything goes through Helm
4. **ServiceAccount name must stay `dagster`** — IRSA trust policy is scoped to this exact name
5. **Namespace must stay `dagster`** — IRSA trust policy is scoped to this exact namespace
6. **Do not add node taints manually** — they are defined in the Terraform EKS module
7. **Spot instances for jobs** — job pods must tolerate eviction; Dagster retries handle this
8. **`pre-install.sh` is idempotent** — safe to re-run, uses `--dry-run=client` checks where appropriate
