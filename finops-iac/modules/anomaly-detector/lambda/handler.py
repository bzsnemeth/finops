"""
FinOps Cost Anomaly Detector

Compares today's spend against a rolling average and alerts
via SNS/Slack when deviations exceed the configured threshold.
"""

import json
import os
import logging
from datetime import datetime, timedelta
from urllib.request import Request, urlopen
from urllib.error import URLError

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ce_client = boto3.client("ce")
sns_client = boto3.client("sns")

THRESHOLD_PCT = int(os.environ.get("ANOMALY_THRESHOLD", 30))
LOOKBACK_DAYS = int(os.environ.get("LOOKBACK_DAYS", 7))
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
SLACK_WEBHOOK = os.environ.get("SLACK_WEBHOOK_URL", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "production")


def get_daily_costs(start_date: str, end_date: str) -> dict:
    """Fetch daily costs grouped by service from Cost Explorer."""
    response = ce_client.get_cost_and_usage(
        TimePeriod={"Start": start_date, "End": end_date},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    daily_costs = {}
    for result in response["ResultsByTime"]:
        date = result["TimePeriod"]["Start"]
        services = {}
        total = 0.0
        for group in result["Groups"]:
            service = group["Keys"][0]
            cost = float(group["Metrics"]["UnblendedCost"]["Amount"])
            services[service] = cost
            total += cost
        daily_costs[date] = {"services": services, "total": total}

    return daily_costs


def detect_anomalies(daily_costs: dict) -> list:
    """Compare most recent day against rolling average."""
    dates = sorted(daily_costs.keys())
    if len(dates) < 2:
        logger.warning("Not enough data points for anomaly detection")
        return []

    latest_date = dates[-1]
    latest = daily_costs[latest_date]
    historical = [daily_costs[d] for d in dates[:-1]]

    # Calculate rolling averages
    avg_total = sum(d["total"] for d in historical) / len(historical)
    all_services = set()
    for d in historical:
        all_services.update(d["services"].keys())

    service_avgs = {}
    for svc in all_services:
        costs = [d["services"].get(svc, 0) for d in historical]
        service_avgs[svc] = sum(costs) / len(costs)

    anomalies = []

    # Check total spend
    if avg_total > 0:
        total_deviation = ((latest["total"] - avg_total) / avg_total) * 100
        if abs(total_deviation) > THRESHOLD_PCT:
            anomalies.append({
                "type": "total",
                "service": "ALL SERVICES",
                "date": latest_date,
                "current": round(latest["total"], 2),
                "average": round(avg_total, 2),
                "deviation_pct": round(total_deviation, 1),
            })

    # Check per-service
    for svc, current_cost in latest["services"].items():
        avg = service_avgs.get(svc, 0)
        if avg > 10:  # skip noise from tiny services
            deviation = ((current_cost - avg) / avg) * 100
            if abs(deviation) > THRESHOLD_PCT:
                anomalies.append({
                    "type": "service",
                    "service": svc,
                    "date": latest_date,
                    "current": round(current_cost, 2),
                    "average": round(avg, 2),
                    "deviation_pct": round(deviation, 1),
                })

    return sorted(anomalies, key=lambda a: abs(a["deviation_pct"]), reverse=True)


def send_sns_alert(anomalies: list) -> None:
    """Publish anomaly alert to SNS topic."""
    if not SNS_TOPIC_ARN:
        return

    subject = f"⚠️ FinOps Alert: {len(anomalies)} cost anomalies detected"
    message = format_text_alert(anomalies)

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject[:100],
        Message=message,
    )
    logger.info(f"SNS alert sent to {SNS_TOPIC_ARN}")


def send_slack_alert(anomalies: list) -> None:
    """Post anomaly alert to Slack webhook."""
    if not SLACK_WEBHOOK:
        return

    blocks = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": f"⚠️ {len(anomalies)} Cost Anomalies Detected"},
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Environment:* `{ENVIRONMENT}` | *Threshold:* ±{THRESHOLD_PCT}% | *Lookback:* {LOOKBACK_DAYS} days",
            },
        },
        {"type": "divider"},
    ]

    for a in anomalies[:5]:  # limit to top 5
        direction = "📈" if a["deviation_pct"] > 0 else "📉"
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": (
                    f"{direction} *{a['service']}*\n"
                    f"Current: `${a['current']:,.2f}` | "
                    f"Avg: `${a['average']:,.2f}` | "
                    f"Deviation: `{a['deviation_pct']:+.1f}%`"
                ),
            },
        })

    payload = {"blocks": blocks}

    try:
        req = Request(
            SLACK_WEBHOOK,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        urlopen(req)
        logger.info("Slack alert sent successfully")
    except URLError as e:
        logger.error(f"Failed to send Slack alert: {e}")


def format_text_alert(anomalies: list) -> str:
    """Format anomalies as plain text for SNS/email."""
    lines = [
        f"FinOps Cost Anomaly Report — {ENVIRONMENT}",
        f"Threshold: ±{THRESHOLD_PCT}% | Lookback: {LOOKBACK_DAYS} days",
        "-" * 50,
    ]
    for a in anomalies:
        direction = "↑" if a["deviation_pct"] > 0 else "↓"
        lines.append(
            f"{direction} {a['service']}: "
            f"${a['current']:,.2f} (avg: ${a['average']:,.2f}) "
            f"— {a['deviation_pct']:+.1f}%"
        )
    return "\n".join(lines)


def handler(event, context):
    """Lambda entry point."""
    logger.info(f"Running anomaly detection with threshold={THRESHOLD_PCT}%, lookback={LOOKBACK_DAYS} days")

    end_date = datetime.utcnow().strftime("%Y-%m-%d")
    start_date = (datetime.utcnow() - timedelta(days=LOOKBACK_DAYS + 1)).strftime("%Y-%m-%d")

    try:
        daily_costs = get_daily_costs(start_date, end_date)
        anomalies = detect_anomalies(daily_costs)

        if anomalies:
            logger.info(f"Detected {len(anomalies)} anomalies")
            send_sns_alert(anomalies)
            send_slack_alert(anomalies)
        else:
            logger.info("No anomalies detected — all clear")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "anomalies_detected": len(anomalies),
                "anomalies": anomalies,
                "period": {"start": start_date, "end": end_date},
            }),
        }

    except Exception as e:
        logger.error(f"Anomaly detection failed: {e}", exc_info=True)
        raise
