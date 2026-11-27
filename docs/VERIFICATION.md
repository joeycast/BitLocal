# BitLocal Feature Verification Guide

This document defines how every core feature, adaptive layout pose, and design invariant in BitLocal is verified across **static guardrails**, **automated unit tests**, **Maestro E2E flows**, and **manual Simulator / device checks**.

---

## 1. Quick Verification Commands

### Static Design & Convention Guardrails (runs in <1s locally and in CI)
```bash
./scripts/verify_design_conventions.sh
```

### Unit Test Suite (`bitlocalTests`)
```bash
xcodebuild test \
  -project bitlocal.xcodeproj \
  -scheme bitlocal \
  -destination 'platform=iOS Simulator,id=840CF0E4-5453-4CD9-90A4-89EE18CA9F00' \
  -only-testing:bitlocalTests
```

### Maestro UI E2E Flows (requires booted Simulator with app installed)
```bash
maestro test bitlocal-maestro/
```

### Visual / Appearance / Dynamic Type Simulator Capture
```bash
# Find booted simulator UDID
xcrun simctl list devices booted

# Capture Light & Dark Mode screenshots
xcrun simctl ui <UDID> appearance light
xcrun simctl io <UDID> screenshot /tmp/bitlocal-light.png

xcrun simctl ui <UDID> appearance dark
xcrun simctl io <UDID> screenshot /tmp/bitlocal-dark.png
```

---

## 2. Feature Verification Matrix

Every feature shipping in BitLocal should map to at least one automated check plus targeted visual/interaction verification where UI is involved.

| Feature | Automated Unit Tests (`bitlocalTests/`) | Static / CI Guardrails | Maestro UI Flow (`bitlocal-maestro/`) | Manual Simulator / Hardware Check |
|---|---|---|---|---|
| **Adaptive Layout & iPhone Duo Resizability** (`AppLayoutMode`, `AdaptiveLeadingSheetSizing`, `SheetGeometryModel`) | `AppLayoutModeTests.swift` (all size-class combos, nil fallbacks, LTR/RTL fold widths, viewport insets) | `verify_design_conventions.sh` (no `UIScreen.main`, no `userInterfaceIdiom`, no `UIRequiresFullScreen`) | — | Verify iPhone, iPhone Duo Outer (portrait/landscape), iPhone Duo Inner (portrait/landscape + fold/unfold), iPad Split View, and RTL (`-AppleTextDirection YES`) |
| **BTC Map V4 Sync, Merge & Caching** (`BTCMapV4Support`, `BTCMapRepository`, `V4PlaceToElementMapper`, `BTCMapV4Contracts`, `MerchantElementStore`, `MerchantSpatialIndex`) | `BTCMapV4SyncTests.swift`, `BTCMapMergeTests.swift`, `V4PlaceRecordDecodingTests.swift`, `V4PlaceToElementMapperTests.swift`, `MerchantElementStoreTests.swift`, `MerchantSpatialIndexTests.swift`, `IdentifiableIndexTests.swift` | No `DispatchSemaphore`, serialized cache I/O, no unsynchronized static `DateFormatter`, `<= 1,000` lines/file | `Merchant-Discovery-And-Filters.yaml` | Cold launch with empty cache vs warm launch with cached catalog; verify viewport pin refresh on pan/zoom |
| **Merchant Search, Categories & Quick Filters** (`MerchantSearchController`, `MerchantSearchEngine`, `MerchantSearchPersistence`, `MerchantChipFilterEngine`, `BusinessesListView`, `ElementCell`) | `MerchantSearchBehaviorTests.swift` (multi-select category OR, attribute AND, pinned selected chips, map-pin sync), `MerchantSearchControllerTests.swift`, `MerchantSearchEngineTests.swift`, `MerchantSearchPersistenceTests.swift`, `SearchTextNormalizerTests.swift`, `V4SearchQueryEncodingTests.swift` | No `Task.sleep(nanoseconds:)`, no `foregroundColor`/`cornerRadius`, `<= 1,000` lines/file | `Merchant-Discovery-And-Filters.yaml` | Toggle multiple category + attribute chips (`Food` + `Coffee` + `Lightning` + `Open Now`) without modifying search text, compose with typed search, confirm map pins & list stay synced, tap **Clear Filters** |
| **Merchant Detail, Live Hours & Verify/Update on BTC Map** (`BusinessDetailView`, `PlacePaymentRailsStrip`, `PlaceDetailsSurface`, `PlaceDescriptionAndReviewsViews`, `PlaceTrustAndBoostSection`) | `OpeningHoursAndFormattingTests.swift`, `AvailablePaymentMethodsChecksTests.swift`, `ElementMapVisibilityTests.swift` | No mixed `NavigationLink(destination:)`, no `View.if()`, `>= 44x44` targets | `Merchant-Discovery-And-Filters.yaml` | Open merchant card, expand hours, copy address/contact (`TactileCopyButton`), tap **Verify or Update on BTC Map** (`btcmap.org/merchant/<id>`) & **Edit on OpenStreetMap** |
| **Saved Places & Offline iCloud Retry** (`SavedPlacesStore` `@Observable`) | `SavedPlacesStoreTests.swift` (toggle, persistence across relaunch, `pendingAdditions`/`pendingRemovals` queuing, CloudKit merge without resurrecting deletions) | — | `Merchant-Discovery-And-Filters.yaml` | Bookmark a merchant in Airplane Mode, relaunch, filter by `Saved`, re-enable network and confirm iCloud sync |
| **Offline Travel Mode** (`NetworkReachabilityMonitor` `@Observable`, `BusinessesListView`) | `NetworkReachabilityMonitorTests.swift` (initial online state, transient blip debounce suppression, sustained offline flip, immediate online recovery) | — | — | Toggle Airplane Mode on device/simulator: confirm Offline Travel Mode banner appears after debounce and disappears immediately on reconnect |
| **Communities & Community Detail** (`CommunityAreasLoader`, `BottomSheetContentView`, `CommunitiesListView`, `CommunityDetailView`) | `CommunityAreasLoaderTests.swift` | No `View.if()`, no `String(localized: ... inflect:)`, value-based navigation only, consistent `LazyVStack` row identity | `Communities-And-Detail.yaml` | Switch to Communities via the map mode button (`Show communities` / `Show merchants`), search/open a community, confirm inflected merchant count (`N merchants`), `𝕏` social link, and back navigation |
| **Navigation Routing & Deep Links** (`BitLocalNavigationRoute`, `PlaceDeepLinkResolver`) | `BitLocalAppIntentsAndRoutingTests.swift`, `PlaceDeepLinkResolverTests.swift`, `V4SearchQueryEncodingTests.swift` | Value-based `NavigationStack(path:)` only | — | Open `https://www.bitlocal.app/place/<id>` universal link (valid + invalid ID → scrollable `ContentUnavailableView`) |
| **App Intents & Siri Shortcuts** (`BitLocalAppIntents`, `BitLocalAppIntentRouter` `@Observable`) | `BitLocalAppIntentsAndRoutingTests.swift` (router enqueue/consume, `MerchantQuickFilter` metadata & localization) | `static let` metadata | — | Trigger Shortcuts app ("Find Nearby Bitcoin Places", "Find Lightning Places", "Open Bitcoin Communities") and verify cold + warm routing |
| **Settings, About & Release Notes** (`SettingsView`, `AboutView`, `ReleaseNotesStore` `@Observable`, `FeatureHintsController` `@Observable`, `AppearanceManager` `@Observable`) | `ReleaseNotesControllerTests.swift`, `FeatureHintsControllerTests.swift` | Native `.insetGrouped`, no unread `@Environment`, no cross-scene `overrideUserInterfaceStyle` | `Settings-And-About.yaml` | Toggle Light/Dark/System without resetting sheet navigation state, toggle ATMs, toggle Distance Units, open About & What's New |
| **Merchant Alerts (CloudKit Digests)** (`MerchantAlerts` `@Observable`, `MerchantAlertsView`, `MerchantAlertCityPickerView`) | `MerchantAlertsModelsTests.swift` (including grammar inflection checks), `scripts/cloudkit_digest_sync.test.mjs` | Native `async` CloudKit APIs, no `String(localized: ... inflect:)` | `Onboarding-Location-Notification-Granted.yaml` | Select city, enable alerts, inspect digest filter in merchant list |
| **Add Business Submission Flow** (`AddBusinessFormView`, `BusinessSubmissionViewModel` `@Observable`, `BusinessHours`, `LocationSearchView`, `ManualLocationEntryView`) | `OpeningHoursAndFormattingTests.swift` (`WeeklyHours.toOSMFormat()`, `CountryList` ISO region localization) | No `autocapitalization`, no silent `(0, 0)` fallback, double-submit guard | — | Step through location search, manual entry (test invalid address alert), hours, payments, and review email composer |
| **Onboarding** (`OnboardingView`, `OnboardingView+AlertsStep`) | — | `verticalSizeClass == .regular`, Reduce Motion support | `Onboarding-Location-Notification-Granted.yaml` | Run fresh install on iPhone + iPhone Duo outer display (short height) + Accessibility XXL Dynamic Type |
| **Geocoding & LRU Cache** (`LRUCache`, `Geocoder` actor pump) | `LRUCacheTests.swift` | `@unchecked Sendable`, structured actor rate-limiting (no GCD queues) | — | Pan across cities and confirm addresses hydrate smoothly without main-thread stalls |

---

## 3. Manual Pre-Release Checklist (iPhone Duo, iPad & Accessibility)

Run before tagging a release or merging major UI changes:

- [ ] **iPhone (standard compact):** Portrait browse, search, merchant detail, community detail, settings sheet, Light & Dark Mode.
- [ ] **iPhone Duo — Outer Display:** Portrait and landscape; verify vertical side-rail toolbar icons & overflow menu, sheet collapse/expand smoothness, and short-height onboarding/empty-state scrollability.
- [ ] **iPhone Duo — Inner Display & Fold Transitions:** Unfolded landscape leading-side collapsible sheet clears center fold (both LTR and RTL); folding/unfolding preserves active merchant/community selection and navigation stack.
- [ ] **iPad & Multitasking:** Full-screen `NavigationSplitView`, Split View (compact half-width switches to compact sheet), Slide Over.
- [ ] **Dynamic Type (Accessibility XXXL):** No clipped buttons, overlapping badges, or unreadable text in `BusinessDetailView`, `CommunityDetailView`, `BusinessesListView`, `MerchantAlertCityPickerView`, `OnboardingView`, and `ReleaseNotesSheetView`.
- [ ] **VoiceOver & Reduce Motion:** Every icon button and picker has a spoken label, decorative icons are hidden, all interactive targets are `≥ 44×44pt`, and Reduce Motion replaces slides/shimmers/scales with opacity fades.
- [ ] **Offline Travel Mode:** Airplane Mode shows cached places, saved bookmarks remain toggleable and sync on reconnect, and banner clears immediately when back online.

---

## 4. Adding a New Feature? Required Verification Steps

1. Follow [`DESIGN.md`](../DESIGN.md) tokens, surface hierarchy, and accessibility rules.
2. Add unit tests in `bitlocalTests/` (and register the new test file in `bitlocal.xcodeproj/project.pbxproj`).
3. Update the Feature Verification Matrix above (and add/update a Maestro flow in `bitlocal-maestro/` for new user journeys).
4. Run `./scripts/verify_design_conventions.sh` and `xcodebuild test` locally (or confirm GitHub Actions `Build` + `Test` pass on the PR).
