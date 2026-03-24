# CI/CD — Claude Context

## Workflow: `dagster-deploy.yml`

**File**: `.github/workflows/dagster-deploy.yml`

### Triggers
- `push` to `master` branch
- `pull_request` targeting `master`

### AWS Authentication
- **Method**: GitHub Actions OIDC (no long-lived AWS credentials)
- **Role**: `github-assume-role` (ARN in `infra/variables.tf`)
- **Account**: `654654329682`
- **OIDC Provider**: `token.actions.githubusercontent.com`
- Role is granted `AmazonEKSClusterAdminPolicy` via EKS access entry

### Deploy Steps
1. Checkout code
2. Configure AWS credentials via OIDC
3. `aws eks update-kubeconfig` — get cluster credentials
4. Generate image tag: `YYYYMMDD-HHMMSS-<git-sha8>`
5. `helm upgrade --install --rollback-on-failure dagster dagster/dagster -f helm/dagster/values-prod.yaml --set <image-tag>`
6. Verify deployment: check webserver and daemon pod status
7. Post summary to GitHub Actions job summary

### Image Tag Format
```
20260323-103300-8cfba0b7
│        │      └── git SHA (first 8 chars)
│        └──────── time (HHMMSS)
└───────────────── date (YYYYMMDD)
```

### Environment Variables / Secrets Required
| Name | Source | Purpose |
|------|--------|---------|
| `AWS_ROLE_ARN` | GitHub Env / var | OIDC role to assume |
| `EKS_CLUSTER_NAME` | Terraform output / var | Target EKS cluster |
| `AWS_REGION` | Hardcoded `ap-southeast-1` | AWS region |

## Rules

1. **Never store AWS Access Keys in GitHub Secrets** — OIDC only
2. **Never push directly to `master`** without CI passing — the workflow is the gate
3. **`--rollback-on-failure` is required** in the Helm command — do not remove it
4. **Do not add `--force` or `--reset-values`** to Helm upgrade — it would wipe non-tracked values
5. **Image tag must be deterministic and traceable** — always include git SHA
6. **PR deploys are dry-run / plan only** — actual deploy only on push to master
7. **Workflow must not store secrets as plaintext** in logs — mask sensitive outputs
8. **Do not add `workflow_dispatch` trigger** without discussing — manual deploys bypass branch protections
9. **Helm repo must be added before upgrade** — `helm repo add dagster https://dagster-io.github.io/helm && helm repo update`
