#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_SCRIPT="$ROOT/scripts/archive_with_bundled_merchants.sh"
PROJECT="$ROOT/bitlocal.xcodeproj"
SCHEME="bitlocal"
CONFIGURATION="Release"
ARCHIVE_PATH="$ROOT/build/bitlocal.xcarchive"
EXPORT_PATH="$ROOT/build/export"
APP_ID="${ASC_APP_ID:-}"
ASC_PROFILE=""
TEAM_ID="${ASC_TEAM_ID:-}"
WAIT_FOR_PROCESSING=0
SKIP_UPLOAD=0
ALLOW_PROVISIONING_UPDATES=0
ARCHIVE_ARGS=()
ARCHIVE_EXTRA_ARGS=()

detect_team_id() {
  local project_path="$1"
  local scheme_name="$2"
  xcodebuild -project "$project_path" -scheme "$scheme_name" -showBuildSettings 2>/dev/null |
    awk -F ' = ' '/DEVELOPMENT_TEAM = / { print $2; exit }'
}

usage() {
  cat <<'EOF'
Usage: scripts/export_and_upload_with_bundled_merchants.sh [options] [-- <extra xcodebuild archive args>]

Options:
  --app APP_ID                  App Store Connect app id. Falls back to ASC_APP_ID.
  --asc-profile NAME            Optional asc auth profile.
  --team-id TEAM_ID             Apple team id. Falls back to ASC_TEAM_ID or Xcode build settings.
  --export-path PATH            IPA export directory. Default: build/export
  --archive-path PATH           Archive output path. Default: build/bitlocal.xcarchive
  --project PATH                Xcode project path.
  --scheme NAME                 Scheme to archive. Default: bitlocal
  --configuration NAME          Build configuration. Default: Release
  --enrichment-json PATH        Pass enrichment JSON through to bundle prep.
  --skip-tests                  Skip xcodebuild test during bundle prep.
  --test-destination DEST       Override the simulator destination used for prep tests.
  --skip-upload                 Stop after exporting the IPA.
  --wait                        Wait for App Store Connect processing after upload.
  --allow-provisioning-updates  Forward -allowProvisioningUpdates to archive/export.
  --help                        Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_ID="$2"
      shift 2
      ;;
    --asc-profile)
      ASC_PROFILE="$2"
      shift 2
      ;;
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --export-path)
      EXPORT_PATH="$2"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="$2"
      ARCHIVE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --project)
      PROJECT="$2"
      ARCHIVE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      ARCHIVE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      ARCHIVE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --enrichment-json|--skip-tests|--test-destination)
      ARCHIVE_ARGS+=("$1")
      if [[ "$1" != "--skip-tests" ]]; then
        ARCHIVE_ARGS+=("$2")
        shift 2
      else
        shift
      fi
      ;;
    --skip-upload)
      SKIP_UPLOAD=1
      shift
      ;;
    --wait)
      WAIT_FOR_PROCESSING=1
      shift
      ;;
    --allow-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=1
      ARCHIVE_ARGS+=("$1")
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      ARCHIVE_EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      ARCHIVE_EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

"$ARCHIVE_SCRIPT" "${ARCHIVE_ARGS[@]}" -- "${ARCHIVE_EXTRA_ARGS[@]}"

mkdir -p "$EXPORT_PATH"
TEAM_ID="${TEAM_ID:-$(detect_team_id "$PROJECT" "$SCHEME")}"
if [[ -z "$TEAM_ID" ]]; then
  echo "Unable to determine DEVELOPMENT_TEAM. Pass --team-id or set ASC_TEAM_ID." >&2
  exit 1
fi

EXPORT_OPTIONS_PLIST="$(mktemp /tmp/bitlocal-export-options.XXXXXX.plist)"
cleanup() {
  rm -f "$EXPORT_OPTIONS_PLIST"
}
trap cleanup EXIT

cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF

EXPORT_COMMAND=(
  xcodebuild
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_PATH"
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
)

if [[ $ALLOW_PROVISIONING_UPDATES -eq 1 ]]; then
  EXPORT_COMMAND+=(-allowProvisioningUpdates)
fi

printf '+'
printf ' %q' "${EXPORT_COMMAND[@]}"
printf '\n'
"${EXPORT_COMMAND[@]}"

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$IPA_PATH" ]]; then
  echo "No IPA found in $EXPORT_PATH after export." >&2
  exit 1
fi

echo "Exported IPA: $IPA_PATH"

if [[ $SKIP_UPLOAD -eq 1 ]]; then
  exit 0
fi

if [[ -z "$APP_ID" ]]; then
  echo "Missing App Store Connect app id. Pass --app or set ASC_APP_ID." >&2
  exit 1
fi

UPLOAD_COMMAND=(asc)
if [[ -n "$ASC_PROFILE" ]]; then
  UPLOAD_COMMAND+=(--profile "$ASC_PROFILE")
fi
UPLOAD_COMMAND+=(builds upload --app "$APP_ID" --ipa "$IPA_PATH")
if [[ $WAIT_FOR_PROCESSING -eq 1 ]]; then
  UPLOAD_COMMAND+=(--wait)
fi

printf '+'
printf ' %q' "${UPLOAD_COMMAND[@]}"
printf '\n'
"${UPLOAD_COMMAND[@]}"
