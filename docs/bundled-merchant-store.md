# Bundled Merchant Store Release Flow

## Purpose

BitLocal now ships with a bundled merchant SQLite database so the app can:

- start with merchant data already on device at first launch
- avoid a full-world merchant fetch during normal local builds
- use `updated_since` incremental sync after launch instead of rebuilding the whole dataset on device
- support stable, locale-aware address rendering from persisted merchant records

The release flow separates `data preparation` from `archive/upload`.

Normal app builds should be fast and deterministic. Full merchant snapshot generation is a release-prep task, not a build phase.

## Main Components

### Bundled merchant database

- `Settings/Resources/BundledMerchants.sqlite`

This is the SQLite snapshot that ships inside the app bundle.

On first launch, the app copies it into `Application Support` and uses that writable copy as the canonical merchant store.

### Runtime merchant store

- `Shared/Helpers/MerchantStore.swift`

This owns the writable SQLite database used by the app at runtime. It stores:

- merchant records
- source BTC Map address fields
- merged/enriched address fields
- sync state
- address enrichment job state
- optional merchant-to-city linkage used by merchant alerts

### Bundled DB generator

- `scripts/build_bundled_merchants_sqlite.py`

This script rebuilds `BundledMerchants.sqlite` from BTC Map data. It can also merge a prebuilt enrichment artifact with `--enrichment-json`.

This script is intentionally **not** part of normal Xcode builds or archive.

### Release-prep validator

- `scripts/prepare_bundled_merchants_release.py`

This script:

1. rebuilds the bundled merchant DB
2. validates that it is non-empty and has required sync metadata
3. runs the test suite by default

Use this when preparing a release snapshot.

### Archive wrapper

- `scripts/archive_with_bundled_merchants.sh`

This script runs release prep first, then performs `xcodebuild clean archive`.

### Export/upload wrapper

- `scripts/export_and_upload_with_bundled_merchants.sh`

This script runs:

1. release prep
2. archive
3. IPA export
4. optional `asc builds upload`

Use this when you want a one-command release flow.

## Merchant Alerts

Merchant alerts remain anchored on canonical city `locationID`, not city strings.

- `Settings/Resources/BundledCities.sqlite`
- `Shared/ViewModels/ContentViewModel.swift`

The merchant bundle generator attempts to resolve merchants to canonical city records and stores:

- `city_location_id`
- `city_key`

Merchant alert digest lookup now reads merchants by merchant ID from the merchant store instead of depending only on the in-memory merchant list.

## Normal Development Behavior

Normal local builds should **not** regenerate the bundled merchant DB.

Expected workflow during development:

- use the checked-in `Settings/Resources/BundledMerchants.sqlite`
- run the app normally
- let the app do threshold-based `updated_since` sync at runtime

The app currently only runs incremental sync if the last successful sync is older than 6 hours.

## Release Workflow

### 1. Rebuild and validate the bundled merchant DB

```bash
python3 scripts/prepare_bundled_merchants_release.py
```

If you have a prebuilt enrichment artifact:

```bash
python3 scripts/prepare_bundled_merchants_release.py --enrichment-json /path/to/enrichment.json
```

### 2. Archive with merchant prep

```bash
scripts/archive_with_bundled_merchants.sh
```

### 3. Archive, export, and upload in one command

```bash
scripts/export_and_upload_with_bundled_merchants.sh --app <ASC_APP_ID>
```

With enrichment and App Store Connect processing wait:

```bash
scripts/export_and_upload_with_bundled_merchants.sh \
  --app <ASC_APP_ID> \
  --enrichment-json /path/to/enrichment.json \
  --wait
```

## Important Rules

- Do not add bundled merchant generation to normal Xcode build phases.
- Do not rely on runtime device geocoding to fill the entire worldwide dataset.
- Use runtime geocoding only for post-release deltas and priority/detail fallback.
- Treat bundled DB generation as a manual or CI release-prep step.
- Commit the refreshed bundled DB artifact before archiving a release if that is the chosen team workflow.

## Notes on Enrichment

The app runtime can merge sparse geocoding results for newly synced merchants, but the intended source of complete first-launch data is the bundled DB shipped with the app.

If bundled pre-enrichment is part of the release process, the enrichment artifact should be generated outside the app and passed into:

```bash
python3 scripts/build_bundled_merchants_sqlite.py --enrichment-json /path/to/enrichment.json
```

or through the higher-level release wrapper scripts above.
