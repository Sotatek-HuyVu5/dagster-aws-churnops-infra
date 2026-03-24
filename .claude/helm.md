# Helm — Claude Context

## Chart

- **Chart**: Official [Dagster Helm chart](https://dagster-io.github.io/helm)
- **Repo name**: `dagster`
- **Release name**: `dagster`
- **Namespace**: `dagster`
- **Values file**: `helm/dagster/values-prod.yaml`

## Key Configuration

### Image
- **Registry**: ECR — `<account>.dkr.ecr.ap-southeast-1.amazonaws.com/churnops/dagster`
- **Tag format**: `YYYYMMDD-HHMMSS-<git-sha8>` (e.g., `20260323-103300-8cfba0b7`)
- **Tag is injected by CI** via `--set dagsterWebserver.image.tag=...`
- Never hardcode a specific image tag in `values-prod.yaml`

### Node Scheduling
| Component | nodeSelector | Tolerations |
|-----------|-------------|-------------|
| webserver | `workload: webserver` | none |
| daemon | `workload: webserver` | none |
| run pods (jobs) | `workload: jobs` | `workload=jobs:NoSchedule` |

### PostgreSQL (External RDS)
- Uses external RDS — `postgresql.enabled: false` (no in-cluster Postgres)
- Connection string sourced from K8s secret `dagster-postgresql-secret`
- Secret key: `postgresql-password`
- SSL required: `sslmode=require`
- Host: RDS endpoint from Terraform output

### Compute Log Manager
- Type: S3
- Bucket: `churnops-data-prod`
- Prefix: `dagster-logs/`
- Region: `ap-southeast-1`

### ServiceAccount
- Name: `dagster`
- Created externally via `k8s/pre-install.sh` (not by Helm)
- Annotated with IRSA role ARN
- `serviceAccount.create: false` in values

### Run Launcher
- Type: `K8sRunLauncher`
- Jobs scheduled on `workload=jobs` nodes with spot tolerations
- Resource requests/limits set on job pods to control spot scheduling

## Rules

1. **Do not enable in-cluster PostgreSQL** (`postgresql.enabled` must stay `false`)
2. **Do not change the release name** from `dagster` — K8s secret names depend on it
3. **Image tag in values-prod.yaml should use a placeholder** like `latest` or `dev` — CI always overrides it
4. **Run `helm diff`** before applying changes manually (use `helm plugin install https://github.com/databus23/helm-diff`)
5. **Helm upgrade command** must always include `--rollback-on-failure`
6. **ServiceAccount must be pre-created** by `k8s/pre-install.sh` before first Helm install
7. **Never store real passwords in values-prod.yaml** — use `existingSecret` references
8. **Resource limits are required** on webserver and daemon pods to prevent node overload on t3.small
