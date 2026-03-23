# Kế hoạch Xây dựng Hạ tầng (Infrastructure Plan) - Project ChurnOps

## 🎯 Mục tiêu
Sử dụng **Terraform** để xây dựng toàn bộ hạ tầng Serverless trên AWS phục vụ cho Data Pipeline (dbt/Redshift) và Machine Learning (SageMaker). Hạ tầng này được thiết kế để tích hợp hoàn hảo với luồng CI/CD (GitHub Actions) nhằm tự động hóa việc deploy code của Dagster.

---

## 🗺️ Các Giai đoạn Triển khai (Phases)

### Phase 1: Nền tảng & Quản lý State (Foundation & State)
- [ ] **S3 Backend:** Tạo bucket S3 (vd: `tf-state-churnops`) để lưu file `terraform.tfstate`.
- [ ] **DynamoDB Lock:** Tạo bảng DynamoDB để khóa state (State Locking), tránh xung đột khi CI/CD chạy đồng thời.
- [ ] **Networking:** Setup VPC, Public/Private Subnets, Internet Gateway và NAT Gateway. (Lưu ý: Redshift và ECS nên đặt trong Private Subnet).

### Phase 2: Lưu trữ & Data Warehouse (Storage & Compute)
- [ ] **Amazon S3 Buckets:**
  - `churnops-data-lake`: Lưu raw data và dữ liệu đã qua dbt (kết quả từ lệnh Redshift `UNLOAD`).
  - `churnops-ml-models`: Lưu trữ file `model.tar.gz` do SageMaker sinh ra.
- [ ] **Amazon Redshift Serverless:**
  - Khởi tạo `aws_redshiftserverless_namespace` (cấu hình db name, admin credentials).
  - Khởi tạo `aws_redshiftserverless_workgroup` (Base RPU = 8 để tối ưu chi phí).

### Phase 3: Bảo mật & Phân quyền (IAM & Security)
Thiết lập quyền "Least Privilege" (Vừa đủ xài):
- [ ] **Redshift Role:** Cấp quyền đọc/ghi (`COPY`, `UNLOAD`) vào bucket `churnops-data-lake`.
- [ ] **SageMaker Role:** Cấp quyền đọc training data từ S3 và ghi artifact (model) lên bucket `churnops-ml-models`.
- [ ] **ECS Task Execution Role:** Cấp quyền cho Dagster container được phép gọi API SageMaker, query Redshift, đọc/ghi S3 và ghi log (CloudWatch).

### Phase 4: Nền tảng Orchestration (ECS Fargate cho Dagster)
- [ ] **Amazon ECR:** Tạo repository chứa Docker image của Dagster + dbt.
- [ ] **Amazon ECS Cluster:** Khởi tạo cluster chạy trên nền Fargate (Serverless compute).
- [ ] **ECS Task Definition:** - Định nghĩa cấu hình CPU/RAM cho Dagster Webserver & Daemon.
  - *Lưu ý:* Biến số hóa (parameterize) Image Tag (không dùng `latest`) để CI/CD có thể truyền Commit SHA vào khi deploy.
- [ ] **ECS Service:** Khởi chạy service để duy trì container Dagster hoạt động 24/7.

### Phase 5: Tự động hóa CI/CD (GitHub Actions)
- [ ] **Pipeline 1 - Deploy Infra:**
  - Trigger: Khi có thay đổi trong thư mục `/terraform`.
  - Action: `terraform init` -> `terraform plan` -> `terraform apply -auto-approve`.
- [ ] **Pipeline 2 - Deploy Data Logic (Dagster/dbt):**
  - Trigger: Khi có thay đổi code Python/SQL.
  - Action: Build Docker Image -> Tag image bằng Commit SHA -> Push lên ECR -> Gọi API update ECS Service để chạy image mới.

---

## 📂 Cấu trúc Thư mục Terraform Đề xuất

```text
terraform/
├── backend.tf         # Cấu hình S3 và DynamoDB cho tfstate
├── providers.tf       # Khai báo AWS Provider & Region
├── variables.tf       # Định nghĩa các biến (vd: ecr_image_tag)
├── vpc.tf             # Cấu hình mạng (VPC, Subnets, Nat Gateway)
├── s3.tf              # Buckets cho Data Lake & ML Models
├── redshift.tf        # Cấu hình Redshift Serverless
├── iam.tf             # Các Roles & Policies
├── ecr.tf             # Nơi chứa Docker image
└── ecs.tf             # Cluster, Task Definition & Service cho Dagster
