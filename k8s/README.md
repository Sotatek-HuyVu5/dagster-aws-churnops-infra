# k8s — Scripts & Manifests

## Files

| File | Mục đích |
|------|----------|
| `pre-install.sh` | Bootstrap K8s trước lần Helm deploy đầu tiên |
| `seed-pod.yaml` | Pod tạm để seed data CSV vào RDS |
| `seed_data.py` | Script Python đọc CSV và insert vào 4 RAW tables |
| `data_sample.csv` | File CSV mẫu |

---

## 1. Pre-install (chạy 1 lần trước Helm deploy)

```bash
bash k8s/pre-install.sh
```

Script sẽ tự động:
- Lấy outputs từ Terraform (cluster name, RDS endpoint, IRSA role ARN, ...)
- Update kubeconfig
- Patch CoreDNS để chạy trên Fargate
- Tạo namespace `dagster`
- Tạo ServiceAccount `dagster-sa` với IRSA annotation
- Lấy RDS password từ Secrets Manager và tạo K8s secrets

---

## 2. Seed data CSV vào RDS

Dùng khi cần đẩy data mẫu vào RDS PostgreSQL để test luồng. Pod chạy trong cluster (cùng VPC với RDS) nên kết nối được dù RDS ở private subnet.

### Yêu cầu
- `pre-install.sh` đã chạy xong (K8s secrets đã tồn tại)
- Có file CSV theo cấu trúc Telco Customer Churn (xem `data_sample.csv`)

### Bước 1 — Deploy pod

```bash
kubectl apply -f k8s/seed-pod.yaml
kubectl wait --for=condition=Ready pod/seed-pod -n dagster --timeout=120s
```

### Bước 2 — Copy files vào pod

```bash
kubectl cp k8s/seed_data.py      dagster/seed-pod:/tmp/seed/seed_data.py
kubectl cp k8s/data_sample.csv   dagster/seed-pod:/tmp/seed/data_sample.csv
# Hoặc thay data_sample.csv bằng file CSV của bạn:
# kubectl cp /path/to/your_data.csv dagster/seed-pod:/tmp/seed/data_sample.csv
```

### Bước 3 — Exec vào pod, cài dependencies và chạy script

```bash
kubectl exec -it -n dagster seed-pod -- bash
```

Trong pod:

```bash
pip install pandas sqlalchemy psycopg2-binary --quiet
python /tmp/seed/seed_data.py /tmp/seed/data_sample.csv
```

Output mong đợi:

```
Starting seed from: /tmp/seed/data_sample.csv
Loading data into RAW tables...
Done. 7043 rows seeded into 4 RAW tables.
```

### Bước 4 — Xóa pod sau khi xong

```bash
kubectl delete -f k8s/seed-pod.yaml
```

### Tables được tạo/cập nhật

| Table | Nội dung |
|-------|----------|
| `raw_customers` | customerID, gender, SeniorCitizen, Partner, Dependents |
| `raw_services` | PhoneService, MultipleLines, InternetService, ... |
| `raw_contracts` | Contract, PaperlessBilling, PaymentMethod, tenure, Churn |
| `raw_billing_history` | billing_id (UUID), MonthlyCharges, billing_date |

> Script dùng `if_exists="append"` — an toàn khi chạy nhiều lần, data sẽ được append thêm.
