#!/usr/bin/env bash
# One-time creation of the PLATFORM secrets that are not managed by Terraform:
# the Grafana admin login and the Alertmanager Slack webhook. External Secrets
# syncs them into the monitoring namespace. The ESO IAM policy allows secret/platform/*.
#
#   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... AWS_REGION=us-east-1 scripts/create-platform-secrets.sh
set -euo pipefail

: "${SLACK_WEBHOOK_URL:?Set SLACK_WEBHOOK_URL (use a placeholder URL if you have no Slack yet)}"
REGION="${AWS_REGION:-us-east-1}"

put() {
  local name="$1" json="$2"
  if aws secretsmanager describe-secret --secret-id "$name" --region "$REGION" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --secret-id "$name" --secret-string "$json" --region "$REGION" >/dev/null
    echo "updated $name"
  else
    aws secretsmanager create-secret --name "$name" --secret-string "$json" --region "$REGION" >/dev/null
    echo "created $name"
  fi
}

PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"
put platform/grafana-admin "$(jq -cn --arg p "$PASSWORD" '{"admin-user":"admin","admin-password":$p}')"
put platform/alertmanager-slack "$(jq -cn --arg u "$SLACK_WEBHOOK_URL" '{url:$u}')"

echo "Grafana admin password: $PASSWORD   (store it in your password manager)"
