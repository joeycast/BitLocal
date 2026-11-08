#!/usr/bin/env bash
# Picks the Xcode for CI. The redesign targets Xcode 27.1+ (needed for iPhone
# Duo's full display and vertical bars, docs/redesign/duo.md section 0); until
# the runner image has it, fall back to the newest installed Xcode 26.
set -euo pipefail

echo "Installed Xcodes:"
ls -d /Applications/Xcode*.app || true

pick=""
for candidate in /Applications/Xcode_27.3.app /Applications/Xcode_27.2.app /Applications/Xcode_27.1.app \
                 /Applications/Xcode_26.4.app /Applications/Xcode_26.3.app; do
  if [ -d "$candidate" ]; then pick="$candidate"; break; fi
done
if [ -z "$pick" ]; then
  pick="$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)"
fi

echo "Selecting $pick"
sudo xcode-select -s "$pick"
xcodebuild -version

# Newest available iPhone 17-class simulator on the newest iOS runtime.
dest_id="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if not d["name"].startswith("iPhone"):
            continue
        plain = re.fullmatch(r"iPhone (\d+)", d["name"])
        rank = (version, plain is not None, int(plain.group(1)) if plain else 0)
        if best is None or rank > best[0]:
            best = (rank, d["udid"], d["name"], runtime)
print(best[1] if best else "")
')"
if [ -z "$dest_id" ]; then
  echo "No iPhone simulator found" >&2
  exit 1
fi
echo "Simulator: $dest_id"
echo "SIM_DESTINATION=platform=iOS Simulator,id=$dest_id" >> "$GITHUB_ENV"
