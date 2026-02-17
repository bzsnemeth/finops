# Tagging Compliance Module

Enforces tagging governance using AWS Config managed rules. Monitors resources for required tags and sends real-time alerts when non-compliant resources are detected.

## What It Does

1. **AWS Config Rule** — Evaluates EC2, RDS, S3, Lambda, ECS, EKS, and ALB resources for required tags
2. **EventBridge** — Catches compliance state changes in real-time
3. **SNS Alerts** — Notifies team when resources are created without required tags
4. **SCP Generation** — Optionally generates a Service Control Policy to prevent untagged resource creation

## Usage

```hcl
module "tagging_compliance" {
  source        = "./modules/tagging-compliance"
  environment   = "production"
  required_tags = ["Environment", "Team", "CostCenter", "Project"]
  alert_email   = "finops@company.com"
  generate_scp  = true
}
```

## Prerequisites

AWS Config must be enabled in the target account/region. If not already configured, enable the Config recorder and delivery channel before deploying this module.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `required_tags` | Tag keys to enforce (max 6) | `["Environment", "Team", "CostCenter", "Project"]` |
| `alert_email` | Email for compliance alerts | `""` |
| `generate_scp` | Generate deny-untagged SCP file | `false` |
