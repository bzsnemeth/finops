# Cost Anomaly Detector Module

Automated daily cost anomaly detection using AWS Cost Explorer, Lambda, and EventBridge. Alerts via SNS (email) and Slack when spending deviates beyond a configurable threshold.

## How It Works

1. **EventBridge** triggers the Lambda function on a cron schedule (default: daily at 8am UTC)
2. **Lambda** queries Cost Explorer for the last N days of spend by service
3. Compares each day and service against a rolling average
4. If deviation exceeds threshold → sends alerts to **SNS** and/or **Slack**

## Usage

```hcl
module "anomaly_detector" {
  source             = "./modules/anomaly-detector"
  environment        = "production"
  anomaly_threshold  = 30
  lookback_days      = 7
  schedule           = "cron(0 8 * * ? *)"
  slack_webhook_url  = var.slack_webhook_url
  alert_email        = "finops@company.com"
}
```

## Alert Format

### Slack
```
⚠️ 2 Cost Anomalies Detected
Environment: production | Threshold: ±30% | Lookback: 7 days
───
📈 Amazon EC2 — Current: $4,280 | Avg: $1,035 | Deviation: +313.5%
📈 Amazon S3  — Current: $890   | Avg: $512   | Deviation: +73.8%
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `anomaly_threshold` | % deviation to trigger alert | `30` |
| `lookback_days` | Rolling average window | `7` |
| `schedule` | EventBridge cron expression | `cron(0 8 * * ? *)` |
| `slack_webhook_url` | Slack webhook (optional) | `""` |
| `alert_email` | Email for SNS subscription (optional) | `""` |
