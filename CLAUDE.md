# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BitLocal is an iOS app that helps users discover physical businesses accepting Bitcoin payments. It displays an interactive map with merchant locations from the BTC Map API, plus communities, events, merchant alerts, and hybrid search.

**Key facts:**
- 100% SwiftUI, iOS 18.0+, zero external dependencies
- Universal app (iPhone + iPad with distinct layouts)
- Bundle ID: `app.bitlocal.bitlocal`
- Scheme name: `bitlocal` (lowercase)

## Build Commands

```bash
# Build for simulator (preferred destination from AGENTS.md)
xcodebuild -scheme bitlocal \
  -destination 'platform=iOS Simulator,id=840CF0E4-5453-4CD9-90A4-89EE18CA9F00'

# Run unit tests
xcodebuild test -scheme bitlocal \
  -destination 'platform=iOS Simulator,id=840CF0E4-5453-4CD9-90A4-89EE18CA9F00'
```

Or use Xcode: `Cmd+B` to build, `Cmd+R` to run, `Cmd+U` for tests.

**Test target:** `bitlocalTests` (XCTest). Covers V4 mapping/sync helpers, search normalizer, merge, LRU cache, feature hints, merchant alerts models, etc.

## Architecture

**MVVM Pattern:**
- Feature folders under `Businesses/`, `Map/`, `Settings/`, `Onboarding/`, `Shared/`
- `ContentViewModel` is the central composition root (location, map session, search, communities, deep links, lifecycle)
- Networking/sync lives in `BTCMapRepository` + versioned clients (v2/v3/v4)

**Key Files:**
- `bitlocalApp.swift` — `@main` entry with scene-phase handling
- `Shared/ViewModels/ContentViewModel.swift` — primary app state
- `Shared/Helpers/BTCMapV4Support.swift` — v4 client, repository, snapshot/incremental sync
- `Shared/Helpers/BTCMapV4Contracts.swift` — v4 DTOs + sync state
- `Shared/Helpers/BtcMapCall.swift` — legacy v2 `APIManager`, `NilOnFail`, `LogManager`
- `Businesses/Models/Element.swift` — merchant model (identity by place `id`)
- `Shared/Helpers/MerchantAlerts.swift` — CloudKit merchant alert digests
- `Map/Views/MapView.swift` — `MKMapView` bridge + annotation coordinator

**Folder Structure:**
```
bitlocal/
├── Businesses/      # Merchant features (models, forms, detail, lists)
├── Map/             # MapKit views and annotations
├── Settings/        # Preferences, merchant alerts UI
├── Shared/          # Networking, ContentViewModel, common UI
├── Onboarding/      # First-launch experience
├── Fonts/           # Custom font registration
├── Resources/       # Font files, BundledCities.sqlite
├── bitlocalTests/   # Unit tests
└── docs/            # Feature notes (e.g. CloudKit alerts)
```

## Data Flow (v4 preferred)

Default repository mode is **auto**: prefer v4, fall back to v2 when needed.

1. On launch: load cached merchants from disk if present  
   - v4: `Caches/btcmap_elements_v4.json` + `btcmap_v4_sync_state.json`  
   - v2 legacy: `Caches/elements.json`
2. Show cached merchants immediately when available
3. If no v4 cache: bootstrap from CDN snapshot  
   `https://cdn.static.btcmap.org/api/v4/places.json`  
   (may use placeholder names until incremental/detail hydration)
4. Incremental sync:  
   `GET https://api.btcmap.org/v4/places?updated_since=<anchor>&include_deleted=true&fields=...`
5. Merge by place id, drop deleted, persist cache + sync anchor
6. Map region changes debounce (~500ms) and refresh annotations in viewport (25-mile cap)

**Other API surfaces:**
- Search: `v4/places/search/`
- Events: `v4/events`
- Communities/areas: v2/v3 area endpoints
- Deep links: place share URLs → single-place fetch

**Caching / invalidation:**
- Geocoding LRU + `geocoding_cache.json`
- App marketing version change clears v2 cache (`APIManager`) and v4 cache files (`BTCMapRepository`)
- Sync schema version on `V4SyncState` drives one-time name backfill when needed

**User-Agent:** `BitLocal-iOS/<version> (<build>; iOS)` via `BTCMapRequestMetadata.appUserAgent`

## Code Patterns

**Property wrappers:**
- `@NilOnFail` — fault-tolerant JSON decoding (returns nil instead of throwing)

**Debug logging:**
- `Debug.log()`, `Debug.logAPI`, `Debug.logCache`, `Debug.logMap`, `Debug.logTiming`
- Map logs gated by `BITLOCAL_MAP_LOGS=1`
- Disabled in Release automatically

**Threading:**
- API/cache I/O on background queues
- UI updates on main thread
- Geocoding single-flight + backoff
- `LRUCache` is lock-protected

## Important Conventions

- iPhone: portrait-oriented product UX, bottom sheet with multiple detents
- iPad: split layout when regular size class; compact multitasking uses phone shell
- Map uses Bitcoin-orange markers (`MarkerColor`); boosted merchants use system orange tint
- ~25-mile radius visible pin range from map center
- Location permission: “When In Use” only (privacy-first)

## External References

- **SPEC.md** — product specification (features, OSM tags, categories)
- **BTC Map API** — https://api.btcmap.org (v2/v3/v4; read-only, no auth)
- **Data attribution** — BTC Map + OpenStreetMap (credited in-app)
