#!/usr/bin/env bash
# Prints Square-related Render env lines from backend/.env with the live hwbg host.
# Does not write anything remote — copy/paste into Render → Environment.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
HOST="https://popup-api-hwbg.onrender.com"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

get() {
  # shellcheck disable=SC2002
  local line
  line="$(grep -E "^${1}=" "$ENV_FILE" | tail -1 || true)"
  echo "${line#*=}"
}

echo "# Paste these into Render → popup-api-hwbg → Environment, then redeploy."
echo "# Also register OAuth + webhook URLs in Square sandbox dashboard."
echo
echo "SQUARE_ENVIRONMENT=sandbox"
echo "SQUARE_APPLICATION_ID=$(get SQUARE_APPLICATION_ID)"
echo "SQUARE_APPLICATION_SECRET=$(get SQUARE_APPLICATION_SECRET)"
echo "SQUARE_ACCESS_TOKEN=$(get SQUARE_ACCESS_TOKEN)"
echo "SQUARE_LOCATION_ID=$(get SQUARE_LOCATION_ID)"
echo "PUBLIC_BASE_URL=$HOST"
echo "SQUARE_OAUTH_REDIRECT_URI=$HOST/api/payments/square/oauth/callback"
echo "SQUARE_WEBHOOK_NOTIFICATION_URL=$HOST/api/payments/square/webhook"
echo "SQUARE_WEBHOOK_SIGNATURE_KEY=$(get SQUARE_WEBHOOK_SIGNATURE_KEY)"
echo
echo "# After webhook is created in Square, replace SQUARE_WEBHOOK_SIGNATURE_KEY."
echo "# Probe: curl -s $HOST/api/payments/health"