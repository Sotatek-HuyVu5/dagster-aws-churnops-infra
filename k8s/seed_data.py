import datetime
import os
import uuid

import pandas as pd
from sqlalchemy import create_engine

# Connection from environment variables — sourced from K8s secret dagster-secrets (pre-install.sh)
POSTGRES_HOST = os.environ["DAGSTER_PG_HOST"]
POSTGRES_PORT = os.getenv("DAGSTER_PG_PORT", "5432")
POSTGRES_DB = os.environ["DAGSTER_PG_DB"]
POSTGRES_USER = os.environ["DAGSTER_PG_USER"]
POSTGRES_PASSWORD = os.environ["DAGSTER_PG_PASSWORD"]
POSTGRES_SCHEMA = os.getenv("POSTGRES_SCHEMA", "public")

DB_URL = f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}?sslmode=require"
engine = create_engine(DB_URL)


def seed_process(file_path: str) -> None:
    print(f"Starting seed from: {file_path}")

    df = pd.read_csv(file_path)

    # Fix TotalCharges (whitespace entries → "0")
    df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce").fillna(0).astype(str)

    # Metadata values shared across all rows in this batch
    batch_date = datetime.date.today().isoformat()
    loaded_at = datetime.datetime.now(datetime.UTC).isoformat()
    s3_source = os.path.basename(file_path)
    partition_key = datetime.datetime.now(datetime.UTC).isoformat()

    metadata = {
        "batch_date": batch_date,
        "partition_key": partition_key,
        "s3_source": s3_source,
        "loaded_at": loaded_at,
    }

    # RAW_CUSTOMERS — all columns VARCHAR, no type conversion
    raw_customers = pd.DataFrame(
        {
            "customer_id": df["customerID"],
            "gender": df["gender"],
            "is_senior_citizen": df["SeniorCitizen"].astype(str),
            "has_partner": df["Partner"],
            "has_dependents": df["Dependents"],
            "created_at": loaded_at,
            **metadata,
        }
    )

    # RAW_SERVICES — raw string values (Yes/No/No internet service)
    raw_services = pd.DataFrame(
        {
            "customer_id": df["customerID"],
            "has_phone_service": df["PhoneService"],
            "has_multiple_lines": df["MultipleLines"],
            "internet_service_type": df["InternetService"],
            "has_online_security": df["OnlineSecurity"],
            "has_online_backup": df["OnlineBackup"],
            "has_device_protection": df["DeviceProtection"],
            "has_tech_support": df["TechSupport"],
            "has_streaming_tv": df["StreamingTV"],
            "has_streaming_movies": df["StreamingMovies"],
            **metadata,
        }
    )

    # RAW_CONTRACTS — raw string values
    raw_contracts = pd.DataFrame(
        {
            "customer_id": df["customerID"],
            "contract_type": df["Contract"],
            "is_paperless_billing": df["PaperlessBilling"],
            "payment_method": df["PaymentMethod"],
            "tenure_months": df["tenure"].astype(str),
            "is_churned": df["Churn"],
            **metadata,
        }
    )

    # RAW_BILLING_HISTORY — billing_id generated as UUID (no SERIAL in raw layer)
    raw_billing_history = pd.DataFrame(
        {
            "billing_id": [str(uuid.uuid4()) for _ in range(len(df))],
            "customer_id": df["customerID"],
            "billing_date": batch_date,
            "amount": df["MonthlyCharges"].astype(str),
            **metadata,
        }
    )

    print("Loading data into RAW tables...")
    schema = POSTGRES_SCHEMA if POSTGRES_SCHEMA != "public" else None

    raw_customers.to_sql("raw_customers", engine, schema=schema, if_exists="append", index=False)
    raw_services.to_sql("raw_services", engine, schema=schema, if_exists="append", index=False)
    raw_contracts.to_sql("raw_contracts", engine, schema=schema, if_exists="append", index=False)
    raw_billing_history.to_sql(
        "raw_billing_history", engine, schema=schema, if_exists="append", index=False
    )

    print(f"Done. {len(df)} rows seeded into 4 RAW tables.")


if __name__ == "__main__":
    import sys
    from pathlib import Path

    default_csv = Path(__file__).parent / "data_sample.csv"
    csv_path = sys.argv[1] if len(sys.argv) > 1 else str(default_csv)
    seed_process(csv_path)
