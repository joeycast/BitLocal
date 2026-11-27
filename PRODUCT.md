# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Bitcoin holders, travelers, and local community members looking for physical businesses, cafés, shops, services, and grassroots Bitcoin communities where they can spend Bitcoin (Lightning, contactless NFC, or on-chain) in the real world.

## Product Purpose

BitLocal makes discovering and visiting physical Bitcoin-accepting merchants effortless on iPhone, iPad, and folding iPhone Duo. Success means a user can open the app—even with poor travel connectivity—immediately see nearby verified merchants on a crisp native map, check live hours and payment methods, bookmark favorites, and navigate straight to the door.

## Positioning

A 100% native SwiftUI, zero-dependency, privacy-first Apple Maps–grade Bitcoin merchant finder powered by open BTC Map and OpenStreetMap data. Unlike web-wrapped directories or cluttered crypto super-apps, BitLocal stays fast, calm, offline-resilient, and deeply integrated with iOS (Liquid Glass, App Intents/Siri Shortcuts, CloudKit private sync, and adaptive iPhone Duo & iPad layouts).

## Operating Context

- Used on the go—often one-handed, outdoors, or while traveling internationally with intermittent connectivity (Offline Travel Mode).
- Backed by read-only open community datasets from BTC Map (v4 primary / v2 fallback, v2/v3 community areas) and OpenStreetMap.
- Merchant corrections and verifications hand off cleanly to `btcmap.org/merchant/<id>` and OpenStreetMap rather than maintaining a proprietary walled-garden database.
- Local-first persistence: cached merchant catalog on disk, private CloudKit sync for saved places and city merchant-alert digests, and "When In Use" location permission only (optional; the app remains fully usable without location sharing).

## Capabilities and Constraints

- **Deployment target:** iOS 18.0+, universal app supporting iPhone, iPad (Split View / Slide Over / full screen), and folding iPhone Duo (outer + inner displays, fold-aware leading sheet, vertical side-rail toolbar on iOS 27.1+).
- **Zero third-party dependencies:** Pure Apple frameworks (`SwiftUI`, `MapKit`, `CoreLocation`, `CloudKit`, `Network`, `AppIntents`, `NaturalLanguage`, `UserNotifications`, `MessageUI`).
- **Core user capabilities:** Interactive clustered map (~25-mile visible pin window), hybrid local + remote merchant search, live utility quick filters (`Saved`, `Open Now`, `Lightning`, `NFC`, `Verified`), merchant & community detail cards, private iCloud saved places with offline retry, Offline Travel Mode, Siri/Shortcuts App Intents, CloudKit city merchant-alert digests, deep links (`bitlocal.app/place/<id>`), and an Add Business submission flow.
- **Feature flags:** Events UI is built but gated off via `FeatureFlags.isEventsUIEnabled`.

## Brand Commitments

- **Name:** BitLocal (`app.bitlocal.bitlocal`)
- **Brand accent:** Warm Bitcoin Orange (`AccentColor`, Display-P3 `#FC780F`) and Map Marker Orange (`MarkerColor`, Display-P3 `#FF6D00`).
- **Wordmark typography:** `Fredoka-Medium` reserved strictly for the `BitLocal` wordmark; native SF Pro Dynamic Type everywhere else.
- **Attribution:** Always credit BTC Map and OpenStreetMap clearly in-app.
- **Privacy:** No third-party analytics SDKs, no tracking, no custody of payments or tips (tipping hands off to the user's chosen Lightning wallet).

## Evidence on Hand

- Product specification: [`SPEC.md`](SPEC.md)
- Visual design system & tokens: [`DESIGN.md`](DESIGN.md)
- Feature verification matrix & release checklists: [`docs/VERIFICATION.md`](docs/VERIFICATION.md)
- Privacy policy: [`Privacy_Policy.md`](Privacy_Policy.md)
- Release history: [`RELEASE_NOTES.md`](RELEASE_NOTES.md)
- Automated tests: `bitlocalTests/` (26 XCTest suites) and `bitlocal-maestro/` (Maestro UI flows).

## Product Principles

1. **Map first, chrome second:** Keep spatial context visible through native translucent materials and collapsible sheets.
2. **Native fluency over novelty:** Follow Apple HIG conventions so every gesture, toolbar, alert, and sheet feels first-party.
3. **Resilient in the real world:** Cached data, offline bookmarking, and clear recovery paths beat silent failures.
4. **Open data, user sovereignty:** Never custody funds, never track users, and route place updates back to BTC Map & OpenStreetMap.
5. **Feature parity across every screen size:** Folding, resizing, or switching to iPad Split View must never hide functionality or drop navigation state.

## Accessibility & Inclusion

- Strict `≥ 44×44pt` touch targets on every interactive control.
- Full Dynamic Type support across all screens (no fixed system font sizes, readable floor at `.caption`).
- Complete VoiceOver labeling, hidden decorative icons, and `accessibilityDifferentiateWithoutColor` compliance (never rely on color alone for open/closed/verified status).
- First-class `@Environment(\.accessibilityReduceMotion)` fallbacks, Light & Dark Mode parity, and LTR/RTL layout support (including iPhone Duo fold clearance).
