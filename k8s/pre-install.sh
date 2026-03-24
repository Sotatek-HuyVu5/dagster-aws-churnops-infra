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

echo "==> Patch CoreDNS để chạy trên Fargate (xoá annotation compute-type: ec2)..."
# Fargate-only cluster: CoreDNS mặc định có annotation eks.amazonaws.com/compute-type=ec2
# Phải xoá annotation này thì Fargate profile mới schedule được CoreDNS pods
kubectl patch deployment coredns \
  -n kube-system \
  --type json \
  -p='[{"op":"remove","path":"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]' \
  2>/dev/null || echo "   (CoreDNS annotation không tồn tại hoặc đã được patch — bỏ qua)"

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
# Ghi ra file để tránh shell expansion với special chars ($, !, etc.)
aws secretsmanager get-secret-value \
  --secret-id churnops/postgres_password \
  --query SecretString \
  --output text \
  | tr -d '\n' > /tmp/pg_password

# Kiểm tra secret tồn tại và có giá trị hợp lệ
PG_LEN=$(wc -c < /tmp/pg_password)
if [ "$PG_LEN" -lt 8 ]; then
  echo "❌ ERROR: Secret 'churnops/postgres_password' trống hoặc không tồn tại (got ${PG_LEN} bytes)."
  echo "   Chạy 'terraform apply' trước để tạo secret, sau đó thử lại."
  rm -f /tmp/pg_password
  exit 1
fi
echo "   ✓ Password lấy được (${PG_LEN} bytes)"

echo "==> Tạo K8s Secret: dagster-postgresql-secret (Helm sẽ dùng, không tự tạo)..."
kubectl delete secret dagster-postgresql-secret --namespace dagster 2>/dev/null || true
kubectl create secret generic dagster-postgresql-secret \
  --namespace dagster \
  --from-file=postgresql-password=/tmp/pg_password
kubectl annotate secret dagster-postgresql-secret --namespace dagster --overwrite \
  "meta.helm.sh/release-name=dagster" "meta.helm.sh/release-namespace=dagster"
kubectl label secret dagster-postgresql-secret --namespace dagster --overwrite \
  "app.kubernetes.io/managed-by=Helm"

echo "==> Tạo K8s Secret: dagster-secrets (env vars cho pods và run jobs)..."
printf '%s' "$RDS_ENDPOINT" > /tmp/pg_host
printf '%s' "$AWS_REGION"   > /tmp/aws_region

kubectl delete secret dagster-secrets --namespace dagster 2>/dev/null || true
kubectl create secret generic dagster-secrets \
  --namespace dagster \
  --from-file=DAGSTER_PG_HOST=/tmp/pg_host \
  --from-literal=DAGSTER_PG_PORT="5432" \
  --from-literal=DAGSTER_PG_DB="dagster" \
  --from-literal=DAGSTER_PG_USER="dagster" \
  --from-file=DAGSTER_PG_PASSWORD=/tmp/pg_password \
  --from-file=AWS_REGION=/tmp/aws_region
kubectl annotate secret dagster-secrets --namespace dagster --overwrite \
  "meta.helm.sh/release-name=dagster" "meta.helm.sh/release-namespace=dagster"
kubectl label secret dagster-secrets --namespace dagster --overwrite \
  "app.kubernetes.io/managed-by=Helm"

rm -f /tmp/pg_host /tmp/aws_region

echo "==> Tạo values override cho Helm (password không lưu vào git)..."
python3 -c "
import sys, yaml
password = open('/tmp/pg_password').read()
print(yaml.dump({'postgresql': {'postgresqlPassword': password}}))
" > /tmp/pg-values-override.yaml
rm -f /tmp/pg_password

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
