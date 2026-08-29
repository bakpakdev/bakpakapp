#!/usr/bin/env bash
# Build the native SwiftUI app and install it on the booted iOS Simulator (or boot iPhone 17 Pro).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ -x "$(command -v python3)" ]]; then
  python3 generate_xcode_project.py
fi

DERIVED="$ROOT/build/DerivedData"
mkdir -p "$ROOT/build"

pick_booted_udid() {
  xcrun simctl list devices booted -j 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for devs in d.get('devices', {}).values():
        for x in devs:
            if x.get('state') == 'Booted':
                print(x['udid'])
                raise SystemExit(0)
except Exception:
    pass
" 2>/dev/null || true
}

UDID="$(pick_booted_udid)"
if [[ -z "${UDID}" ]]; then
  DEFAULT_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
  xcrun simctl boot "$DEFAULT_NAME" 2>/dev/null || true
  open -a Simulator 2>/dev/null || true
  sleep 2
  UDID="$(pick_booted_udid)"
fi
if [[ -z "${UDID}" ]]; then
  echo "No booted simulator. Boot one in Simulator.app or set SIMULATOR_NAME." >&2
  exit 1
fi

xcodebuild \
  -project PopupApp.xcodeproj \
  -scheme PopupApp \
  -destination "id=$UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/PopupApp.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.popup.app
echo "Installed and launched on $UDID"
