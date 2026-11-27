#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="app.bitlocal.bitlocal"
DEVICE_NAME="iPhone 17"
UDID=""
APP_PATH=""
OUTPUT_DIR="build/screenshots"
WAIT_ONBOARDING_SECONDS=3
WAIT_MAP_SECONDS=8

usage() {
  cat <<'EOF'
Usage: scripts/capture_sim_screenshots.sh --app <path/to/bitlocal.app> [options]

Options:
  --app <path>       Path to compiled bitlocal.app bundle (required)
  --udid <udid>      Simulator UDID (auto-resolves an available iPhone if omitted)
  --device <name>    Preferred simulator name when auto-resolving (default: "iPhone 17")
  --output <dir>     Directory to write PNG screenshots (default: build/screenshots)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --udid)
      UDID="$2"
      shift 2
      ;;
    --device)
      DEVICE_NAME="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Error: --app must point to an existing .app bundle." >&2
  exit 1
fi

if [[ -z "$UDID" ]]; then
  UDID="$(
    xcrun simctl list devices available -j | python3 - "$DEVICE_NAME" <<'PY'
import json
import sys

preferred = sys.argv[1]
data = json.load(sys.stdin)
devices = []
for runtime, items in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for item in items:
        if item.get("isAvailable"):
            devices.append((runtime, item))

# Prefer exact name match on newest iOS runtime, then any iPhone.
devices.sort(key=lambda pair: pair[0], reverse=True)
for _, item in devices:
    if item.get("name") == preferred:
        print(item["udid"])
        sys.exit(0)
for _, item in devices:
    if "iPhone" in item.get("name", ""):
        print(item["udid"])
        sys.exit(0)
sys.exit(1)
PY
  )"
fi

if [[ -z "$UDID" ]]; then
  echo "Error: could not resolve an available iOS Simulator device." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

cleanup() {
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Using simulator UDID: $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

# Normalize status bar and simulate a merchant-dense city (Austin, TX).
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4
xcrun simctl location "$UDID" set 30.2672,-97.7431

# Fresh install for deterministic state.
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

capture() {
  local name="$1"
  local appearance="$2"
  local wait_secs="$3"
  shift 3

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  sleep "$wait_secs"

  local out_file="${OUTPUT_DIR}/${name}.png"
  xcrun simctl io "$UDID" screenshot "$out_file"
  if [[ ! -s "$out_file" ]]; then
    echo "Error: screenshot $out_file was not written." >&2
    exit 1
  fi
  echo "Captured $out_file"
}

capture "01-onboarding-light" light "$WAIT_ONBOARDING_SECONDS"
capture "02-onboarding-dark" dark "$WAIT_ONBOARDING_SECONDS"
capture "03-map-sheet-light" light "$WAIT_MAP_SECONDS" -didCompleteOnboarding YES -lastSeenHintCampaignID v1
capture "04-map-sheet-dark" dark "$WAIT_MAP_SECONDS" -didCompleteOnboarding YES -lastSeenHintCampaignID v1

echo "All screenshots captured in $OUTPUT_DIR"
