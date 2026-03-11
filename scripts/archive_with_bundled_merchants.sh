#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREPARE_SCRIPT="$ROOT/scripts/prepare_bundled_merchants_release.py"
PROJECT="$ROOT/bitlocal.xcodeproj"
SCHEME="bitlocal"
CONFIGURATION="Release"
ARCHIVE_PATH="$ROOT/build/bitlocal.xcarchive"
TEST_DESTINATION="platform=iOS Simulator,id=03C5F5DD-9BA9-4517-9110-867844323DD3"
PREPARE_ARGS=()
ARCHIVE_ARGS=()
SKIP_PREPARE=0
ALLOW_PROVISIONING_UPDATES=0

usage() {
  cat <<'EOF'
Usage: scripts/archive_with_bundled_merchants.sh [options] [-- <extra xcodebuild args>]

Options:
  --enrichment-json PATH       Pass enrichment JSON through to bundle prep.
  --skip-tests                 Skip xcodebuild test during bundle prep.
  --test-destination DEST      Override the simulator destination used for prep tests.
  --project PATH               Xcode project path for archive/test.
  --scheme NAME                Scheme to archive. Default: bitlocal
  --configuration NAME         Build configuration. Default: Release
  --archive-path PATH          Archive output path.
  --skip-prepare               Archive without rebuilding the bundled merchant DB.
  --allow-provisioning-updates Forward -allowProvisioningUpdates to xcodebuild archive.
  --help                       Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enrichment-json)
      PREPARE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --skip-tests)
      PREPARE_ARGS+=("$1")
      shift
      ;;
    --test-destination)
      TEST_DESTINATION="$2"
      PREPARE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --project)
      PROJECT="$2"
      PREPARE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      PREPARE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --skip-prepare)
      SKIP_PREPARE=1
      shift
      ;;
    --allow-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      ARCHIVE_ARGS+=("$@")
      break
      ;;
    *)
      ARCHIVE_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ $SKIP_PREPARE -eq 0 ]]; then
  python3 "$PREPARE_SCRIPT" "${PREPARE_ARGS[@]}"
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")"

COMMAND=(
  xcodebuild
  clean
  archive
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -archivePath "$ARCHIVE_PATH"
  -destination "generic/platform=iOS"
)

if [[ $ALLOW_PROVISIONING_UPDATES -eq 1 ]]; then
  COMMAND+=(-allowProvisioningUpdates)
fi

COMMAND+=("${ARCHIVE_ARGS[@]}")

printf '+'
printf ' %q' "${COMMAND[@]}"
printf '\n'
"${COMMAND[@]}"
