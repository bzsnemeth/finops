# CUR Pipeline Module

Deploys a complete AWS Cost and Usage Report (CUR) data pipeline that enables cost querying via Athena.

## What It Does

1. **S3 Bucket** — Receives CUR Parquet data with encryption, versioning, and lifecycle policies
2. **Glue Crawler** — Automatically catalogs CUR data on a schedule
3. **Athena Workgroup** — Pre-configured workspace with result encryption
4. **Named Queries** — Ready-to-use FinOps queries:
   - Daily spend by service
   - Cost allocation by team tag
   - Untagged resource spend
   - Savings Plan / RI coverage analysis

## Usage

```hcl
module "cur_pipeline" {
  source               = "./modules/cur-pipeline"
  environment          = "production"
  bucket_name          = "acme-corp-cur-data"
  athena_database_name = "finops"
  crawler_schedule     = "cron(0 1 * * ? *)"
  retention_days       = 730
}
```

## Prerequisites

CUR must be enabled in the AWS Billing Console with Parquet format and resource IDs included. CUR can only be configured in `us-east-1`.

## Outputs

| Name | Description |
|------|-------------|
| `cur_bucket_arn` | ARN of the CUR S3 bucket |
| `athena_database_name` | Glue/Athena database name |
| `athena_workgroup_name` | Athena workgroup for running queries |
