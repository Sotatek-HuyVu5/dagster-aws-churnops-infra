#!/usr/bin/env bash
# Chạy script này 1 lần trước khi helm install
# Yêu cầu: terraform apply đã xong, aws cli + kubectl đã config

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Lấy outputs từ Terraform..."
cd "$ROOT_DIR/infra"

EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
DAGSTER_IRSA_ROLE_ARN=$(terraform output -raw dagster_irsa_role_arn)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
ECR_URI=$(terraform output -raw dagster_ecr_repo_url)
DATA_BUCKET=$(terraform output -raw data_bucket_name)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "ap-southeast-1")

echo "==> Update kubeconfig..."
aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"

echo "==> Tạo namespace dagster..."
kubectl create namespace dagster --dry-run=client -o yaml | kubectl apply -f -

echo "==> Tạo ServiceAccount với IRSA annotation + Helm ownership labels..."
kubectl create serviceaccount dagster-sa \
  --namespace dagster \
  --dry-run=client -o yaml \
  | kubectl annotate --local -f - \
    "eks.amazonaws.com/role-arn=$DAGSTER_IRSA_ROLE_ARN" \
    "meta.helm.sh/release-name=dagster" \
    "meta.helm.sh/release-namespace=dagster" \
    --overwrite -o yaml \
  | kubectl label --local -f - \
    "app.kubernetes.io/managed-by=Helm" \
    --overwrite -o yaml \
  | kubectl apply -f -

echo "==> Lấy RDS password từ Secrets Manager..."
PG_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id churnops/postgres_password \
  --query SecretString \
  --output text)

HELM_ANNOTATIONS=(
  "meta.helm.sh/release-name=dagster"
  "meta.helm.sh/release-namespace=dagster"
)
HELM_LABELS=(
  "app.kubernetes.io/managed-by=Helm"
)

echo "==> Tạo K8s Secret: dagster-postgresql-secret (dùng bởi Helm chart)..."
kubectl create secret generic dagster-postgresql-secret \
  --namespace dagster \
  --from-literal=postgresql-password="$PG_PASSWORD" \
  --dry-run=client -o yaml \
  | kubectl annotate --local -f - "${HELM_ANNOTATIONS[@]}" --overwrite -o yaml \
  | kubectl label --local -f - "${HELM_LABELS[@]}" --overwrite -o yaml \
  | kubectl apply -f -

echo "==> Tạo K8s Secret: dagster-secrets (env vars cho pods và run jobs)..."
kubectl create secret generic dagster-secrets \
  --namespace dagster \
  --from-literal=DAGSTER_PG_HOST="$RDS_ENDPOINT" \
  --from-literal=DAGSTER_PG_PORT="5432" \
  --from-literal=DAGSTER_PG_DB="dagster" \
  --from-literal=DAGSTER_PG_USER="dagster" \
  --from-literal=DAGSTER_PG_PASSWORD="$PG_PASSWORD" \
  --from-literal=AWS_REGION="$AWS_REGION" \
  --dry-run=client -o yaml \
  | kubectl annotate --local -f - "${HELM_ANNOTATIONS[@]}" --overwrite -o yaml \
  | kubectl label --local -f - "${HELM_LABELS[@]}" --overwrite -o yaml \
  | kubectl apply -f -

echo "==> Update values-prod.yaml..."
VALUES_FILE="$ROOT_DIR/helm/dagster/values-prod.yaml"
sed -i "s|REPLACE_WITH_ECR_URI|$ECR_URI|g"              "$VALUES_FILE"
sed -i "s|REPLACE_WITH_RDS_ENDPOINT|$RDS_ENDPOINT|g"    "$VALUES_FILE"
sed -i "s|REPLACE_WITH_DATA_BUCKET_NAME|$DATA_BUCKET|g" "$VALUES_FILE"

echo "==> Add Dagster Helm repo..."
helm repo add dagster https://dagster-io.github.io/helm
helm repo update

echo ""
echo "✅ Done. Chạy helm install tiếp theo:"
echo "   helm upgrade --install dagster dagster/dagster -f $VALUES_FILE -n dagster"
