#!/usr/bin/env bash
# Generate a local Stripe webhook signing secret (whsec_...) and write it to backend/.env
# Run this in Terminal.app (not Cursor) while developing payments.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
STRIPE_BIN="${STRIPE_BIN:-$HOME/.local/bin/stripe}"

if [[ ! -x "$STRIPE_BIN" ]]; then
  echo "Stripe CLI not found at $STRIPE_BIN"
  echo "Install: https://stripe.com/docs/stripe-cli"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  exit 1
fi

SK="$(python3 - <<PY
from pathlib import Path
for line in Path("$ENV_FILE").read_text().splitlines():
    if line.startswith("STRIPE_SECRET_KEY="):
        print(line.split("=",1)[1].strip().strip('"'))
        break
PY
)"

if [[ -z "$SK" ]]; then
  echo "STRIPE_SECRET_KEY missing in .env"
  exit 1
fi

LIVE_FLAG=()
if [[ "$SK" == sk_live_* ]]; then
  echo "Detected LIVE secret key."
  echo "stripe listen cannot use sk_live via --api-key."
  echo "Do this instead in Terminal:"
  echo "  $STRIPE_BIN login"
  echo "  $STRIPE_BIN listen --live --forward-to http://127.0.0.1:5001/api/payments/webhook"
  echo "Then paste the printed whsec_... into STRIPE_WEBHOOK_SECRET in backend/.env"
  echo ""
  echo "Recommended for development: switch .env + iOS Secrets to TEST keys (sk_test_ / pk_test_)."
  exit 2
fi

echo "Starting stripe listen (test mode). Keep this terminal open while testing payments."
echo "Forwarding -> http://127.0.0.1:5001/api/payments/webhook"
echo ""

# Print secret once, update .env, then keep forwarding.
SECRET="$("$STRIPE_BIN" listen --api-key "$SK" --print-secret)"
python3 - <<PY
from pathlib import Path
secret = """$SECRET""".strip()
path = Path("$ENV_FILE")
lines = []
found = False
for line in path.read_text().splitlines():
    if line.startswith("STRIPE_WEBHOOK_SECRET="):
        lines.append(f"STRIPE_WEBHOOK_SECRET={secret}")
        found = True
    else:
        lines.append(line)
if not found:
    lines.append(f"STRIPE_WEBHOOK_SECRET={secret}")
path.write_text("\\n".join(lines) + "\\n")
print("Updated STRIPE_WEBHOOK_SECRET in backend/.env")
print("Restart your backend server so it picks up the new value.")
PY

exec "$STRIPE_BIN" listen \
  --api-key "$SK" \
  --forward-to http://127.0.0.1:5001/api/payments/webhook \
  --events payment_intent.succeeded,payment_intent.payment_failed,account.updated
