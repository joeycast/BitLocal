#!/usr/bin/env bash
# Visual UI check for CI: installs the Debug simulator build on an iPhone, an iPad
# and (when the runtime has one) an iPhone Duo, opens each debug scenario
# (`UICheckScenario` in ContentViewModel.swift) and prints a downscaled JPEG of
# each screen into the log as base64 lines:
#   UICHECK <device>-<scenario> <chunk index> <base64 chunk>
# The PNGs are also uploaded as the `ui-check` artifact. Never fails the build.
set -uo pipefail

APP="$(ls -d build/DerivedData/Build/Products/Debug-iphonesimulator/*.app | grep -v Tests | head -1)"
BUNDLE_ID="app.bitlocal.bitlocal"
OUT="build/ui-check"
mkdir -p "$OUT"
echo "App: $APP"

# Nashville, the app's default region.
LAT=36.1627
LON=-86.7816

pick_device() {
  # $1: python regex for the device name. Newest iOS runtime wins.
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
pattern = re.compile(sys.argv[1])
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if pattern.search(d["name"]):
            if best is None or version > best[0]:
                best = (version, d["udid"], d["name"])
print(best[1] if best else "")
' "$1"
}

emit() {
  # $1: label, $2: png path
  local jpg="$OUT/$1.jpg"
  sips -Z 900 -s format jpeg -s formatOptions 60 "$2" --out "$jpg" >/dev/null 2>&1 || return
  base64 -i "$jpg" | tr -d '\n' | fold -w 6000 | awk -v label="$1" '{ printf "UICHECK %s %d %s\n", label, NR, $0 }'
}

run_device() {
  local label="$1" udid="$2"
  [ -n "$udid" ] || { echo "No $label simulator; skipping"; return; }
  echo "::group::UI check on $label ($udid)"
  xcrun simctl boot "$udid" 2>/dev/null
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 2>/dev/null
  xcrun simctl ui "$udid" appearance light
  # Start clean: the unit tests ran in this simulator and left a saved search.
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null
  xcrun simctl install "$udid" "$APP"
  xcrun simctl privacy "$udid" grant location "$BUNDLE_ID"
  xcrun simctl location "$udid" set "$LAT,$LON"

  for scenario in browse search communities community digest dark; do
    local name="$scenario" appearance="light"
    if [ "$scenario" = "dark" ]; then name="browse"; appearance="dark"; fi
    xcrun simctl ui "$udid" appearance "$appearance"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null
    local log="$OUT/$label-$scenario.log"
    : > "$log"
    xcrun simctl launch --stdout="$PWD/$log" --stderr="$PWD/$log" "$udid" "$BUNDLE_ID" \
      -didCompleteOnboarding YES -lastSeenHintCampaignID v1 -UICheckScenario "$name" >/dev/null
    # First launch downloads the catalog; later launches read the cache.
    local waited=0
    until grep -q "UICheck: ready" "$log" 2>/dev/null || [ $waited -ge 180 ]; do
      sleep 2; waited=$((waited + 2))
    done
    grep "UICheck:" "$log" || echo "UICheck marker missing after ${waited}s"
    sleep 6
    local png="$OUT/$label-$scenario.png"
    xcrun simctl io "$udid" screenshot --type=png "$png" >/dev/null 2>&1
    emit "$label-$scenario" "$png"
  done
  xcrun simctl ui "$udid" appearance light
  xcrun simctl shutdown "$udid" 2>/dev/null
  echo "::endgroup::"
}

IPHONE="${SIM_DESTINATION##*id=}"
IPAD="$(pick_device '^iPad (Pro 11|Air 11)')"
[ -n "$IPAD" ] || IPAD="$(pick_device '^iPad')"
DUO="$(pick_device 'Duo')"

run_device iphone "$IPHONE"
run_device ipad "$IPAD"
run_device duo "$DUO"
exit 0
