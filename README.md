# ☁️ AWS FinOps Toolkit

Terraform modules for automated cloud cost visibility, anomaly detection, and governance on AWS.

> **Portfolio project** — demonstrates FinOps engineering patterns including CUR pipeline automation, cost anomaly alerting, and tagging compliance enforcement.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS FinOps Toolkit                           │
├─────────────────────┬──────────────────────┬────────────────────────┤
│   CUR Pipeline      │  Anomaly Detector    │  Tagging Compliance    │
│                     │                      │                        │
│  CUR ──► S3 Bucket  │  EventBridge (cron)  │  AWS Config Rules      │
│           │         │       │              │       │                │
│      Glue Crawler   │   Lambda Function    │  Evaluation Results    │
│           │         │       │              │       │                │
│      Athena DB      │  Cost Explorer API   │  SNS Notifications    │
│           │         │       │              │       │                │
│    QuickSight /     │  Anomaly Detection   │  Auto-Remediation     │
│    Grafana Ready    │       │              │  (optional)            │
│                     │  SNS + Slack Alert   │                        │
└─────────────────────┴──────────────────────┴────────────────────────┘
```

## Modules

| Module | Description | Key Resources |
|--------|-------------|---------------|
| [`cur-pipeline`](./modules/cur-pipeline) | Deploys CUR export → S3 → Glue → Athena pipeline for cost queryability | S3, Glue Crawler, Athena DB, IAM |
| [`anomaly-detector`](./modules/anomaly-detector) | Lambda-based daily cost anomaly detection with Slack/SNS alerting | Lambda, EventBridge, SNS, IAM |
| [`tagging-compliance`](./modules/tagging-compliance) | AWS Config rules for tag enforcement with compliance reporting | Config Rules, SNS, IAM |

## Quick Start

```hcl
module "cur_pipeline" {
  source      = "./modules/cur-pipeline"
  environment = "production"
  bucket_name = "my-company-cur-data"
  athena_database_name = "finops"
}

module "anomaly_detector" {
  source             = "./modules/anomaly-detector"
  environment        = "production"
  slack_webhook_url  = var.slack_webhook_url
  anomaly_threshold  = 30  # alert on >30% deviation
  schedule           = "cron(0 8 * * ? *)"  # daily at 8am UTC
}

module "tagging_compliance" {
  source          = "./modules/tagging-compliance"
  environment     = "production"
  required_tags   = ["Environment", "Team", "CostCenter", "Project"]
  alert_email     = "finops@company.com"
}
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate permissions
- AWS Account with Cost Explorer and CUR enabled
- (Optional) Slack webhook URL for anomaly alerts

## Repository Structure

```
.
├── modules/
│   ├── cur-pipeline/          # CUR → S3 → Athena pipeline
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── anomaly-detector/      # Cost anomaly detection + alerting
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── lambda/
│   │   │   └── handler.py
│   │   └── README.md
│   └── tagging-compliance/    # Tag enforcement via AWS Config
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
├── examples/
│   └── complete/              # Full deployment example
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars.example
├── docs/
│   └── architecture.md
├── .gitignore
├── LICENSE
└── README.md
```

## Cost Savings Demonstrated

This toolkit addresses the most common sources of cloud waste:

| Optimization Area | Typical Savings | Module |
|-------------------|----------------|--------|
| Cost visibility & accountability | 10–15% (behavioral) | `cur-pipeline` |
| Anomaly detection & fast response | 5–8% (waste prevention) | `anomaly-detector` |
| Tagging compliance & allocation | 3–5% (governance) | `tagging-compliance` |
| **Combined** | **18–28%** | All |

## License

MIT

## Author

Built by [Bator Nemeth](https://yourname.cloud) — AWS Solutions Architect & FinOps Practitioner.
