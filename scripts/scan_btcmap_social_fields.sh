#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

BASE_URL="https://api.btcmap.org/v4/places/search/"
LIMIT="${LIMIT:-500}"
OUTPUT="${OUTPUT:-}"

# Broad set of single-letter and keyword queries to sample diverse records.
DEFAULT_QUERIES=(
  a b c d e f g h i j k l m
  n o p q r s t u v w x y z
  bitcoin coffee cafe market hotel bar food
)

if [[ $# -gt 0 ]]; then
  QUERIES=("$@")
else
  QUERIES=("${DEFAULT_QUERIES[@]}")
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

keys_file="$TMP_DIR/keys.txt"
all_keys_file="$TMP_DIR/all_keys.txt"
: > "$keys_file"
: > "$all_keys_file"

fetched=0
failed=0

for q in "${QUERIES[@]}"; do
  encoded_q="$(printf '%s' "$q" | jq -sRr @uri)"
  url="${BASE_URL}?name=${encoded_q}&limit=${LIMIT}"

  if body="$(curl -fsS "$url")"; then
    fetched=$((fetched + 1))

    # Capture all keys seen in this response.
    printf '%s' "$body" | jq -r 'map(keys) | add | .[]' >> "$all_keys_file"

    # Capture only social-like keys for quick review.
    printf '%s' "$body" | jq -r 'map(keys) | add | .[]' \
      | rg -i 'twitter|facebook|instagram|telegram|line|tiktok|youtube|linkedin|nostr|mastodon|threads|social' \
      >> "$keys_file" || true
  else
    failed=$((failed + 1))
    echo "warn: request failed for query '$q'" >&2
  fi
done

# Unique sorted outputs.
sort -u "$all_keys_file" > "$TMP_DIR/all_keys_unique.txt"
sort -u "$keys_file" > "$TMP_DIR/social_keys_unique.txt"

report="$TMP_DIR/report.txt"
{
  echo "BTCMap v4 Social Field Scan"
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Base URL: $BASE_URL"
  echo "Queries attempted: ${#QUERIES[@]}"
  echo "Requests succeeded: $fetched"
  echo "Requests failed: $failed"
  echo
  echo "Detected social-like keys:"
  if [[ -s "$TMP_DIR/social_keys_unique.txt" ]]; then
    sed 's/^/- /' "$TMP_DIR/social_keys_unique.txt"
  else
    echo "- (none detected)"
  fi
  echo
  echo "All keys seen across sample:"
  sed 's/^/- /' "$TMP_DIR/all_keys_unique.txt"
} > "$report"

if [[ -n "$OUTPUT" ]]; then
  mkdir -p "$(dirname "$OUTPUT")"
  cp "$report" "$OUTPUT"
  echo "wrote report to: $OUTPUT"
fi

cat "$report"
