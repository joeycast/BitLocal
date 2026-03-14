# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BitLocal is an iOS app that helps users discover physical businesses accepting Bitcoin payments. It displays an interactive map with merchant locations from the BTC Map API.

**Key facts:**
- 100% SwiftUI, iOS 18.0+, zero external dependencies
- Universal app (iPhone + iPad with distinct layouts)
- Bundle ID: app.bitlocal.bitlocal

## Build Commands

```bash
# Build for simulator
xcodebuild -scheme BitLocal -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests (no test target currently configured)
xcodebuild test -scheme BitLocal -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or use Xcode: `Cmd+B` to build, `Cmd+R` to run.

## Architecture

**MVVM Pattern:**
- `Views/` - SwiftUI views (presentation only)
- `ViewModels/` - Business logic with @Published state
- `Models/` - Codable data structures

**Key Files:**
- `bitlocalApp.swift` - @main entry point with scene phase management
- `Shared/ViewModels/ContentViewModel.swift` - Central state (location, data fetching, lifecycle)
- `Shared/Helpers/BtcMapCall.swift` - API calls, file caching, LRU geocoding cache
- `Businesses/Models/Element.swift` - Bitcoin merchant data model from BTC Map API

**Folder Structure:**
```
bitlocal/
├── Businesses/      # Merchant features (models, forms, detail views)
├── Map/             # MapKit views and annotations
├── Settings/        # Preferences (appearance, units, map type)
├── Shared/          # Common components, extensions, networking
├── Onboarding/      # First-launch experience
├── Fonts/           # Custom font registration (Fredoka, Ubuntu)
└── Resources/       # Font files
```

## Data Flow

1. On launch: Load cached `elements.json` from Caches directory
2. Display cached merchants immediately
3. Fetch incremental updates via `GET https://api.btcmap.org/v2/elements?updated_since=<timestamp>`
4. Merge updates, filter deleted, save to cache
5. Map region changes trigger debounced (500ms) annotation updates

**Caching:**
- File-based: `elements.json` in app Caches directory
- LRU geocoding cache (100 entries): `geocoding_cache.json`
- Cache invalidates on app version change

## Code Patterns

**Property wrappers:**
- `@NilOnFail` - Fault-tolerant JSON decoding (returns nil instead of throwing)

**Debug logging:**
- Use `Debug.log()` with categories: `.api`, `.cache`, `.map`, `.general`
- Disabled in Release builds automatically

**Threading:**
- API/cache I/O on background threads
- UI updates on main thread only
- Geocoding rate-limited to 1 concurrent request

## Important Conventions

- iPhone: Portrait only, bottom sheet with 3 detents
- iPad: All orientations, split-view layout (sidebar + map)
- Map uses Bitcoin-orange markers (`MarkerColor` in assets)
- 25-mile radius visible range from map center
- Location permission: "When In Use" only (privacy-first)

## External References

- **SPEC.md** - Comprehensive product specification (2000+ lines) covering all features, OSM tags, business categories, and architectural decisions
- **BTC Map API**: https://api.btcmap.org/v2/elements (read-only, no auth required)
- **Data Attribution**: BTC Map + OpenStreetMap (credited in-app)
