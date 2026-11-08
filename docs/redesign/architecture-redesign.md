# BitLocal Architecture Redesign Spec

Status: approved by Joe 2026-11-08 (design and planning only, no code changed). Removing the BTC Map v2 fallback (section 15) is decided.
Date: 2026-11-08
Companion to: [`ui-redesign.md`](ui-redesign.md). The two documents describe one redesign: the UI spec says what people see and feel, this spec says what the app is built from so that feel is achievable (instant selection, no-jank map, instant search, state that survives resizing and folding).
Source studied: `github.com/joeycast/BitLocal` @ `c0d5210` (fresh clone).
Lens: Emil Kowalski's design-engineering philosophy (`/emil-design-eng`) applied to architecture: the interface can only feel instant if the data layer never makes the main thread wait. Every performance budget below exists because a UI interaction in `ui-redesign.md` depends on it.
Scope: v4-only `Merchant` model, SQLite store with R-tree viewport queries and FTS5 search, clustering instead of the 25-mile pin cap, a single navigation model owning selection / sheet / inspector / deep links, small `@Observable` feature models, Swift 6. **Events stay out of scope.**

---

## 0. Summary

Today almost everything flows through one 3,026-line `ContentViewModel` that is simultaneously the location delegate, the map delegate, the search host, the sync coordinator, the communities loader, the deep-link router and the sheet-geometry tracker. Merchants are stored as v4 data squeezed into the old v2/OpenStreetMap-shaped `Element`, cached as a 20 MB JSON file that is fully decoded into memory on every cold launch, and filtered in memory with a hand-built spatial index and a scanning search engine.

The redesign splits this into four layers with one direction of dependency:

```
App          AdaptiveRootView · AppNavigation (selection, sheet, inspector, deep links)
  │
Features     MapModel · BrowseModel · SearchModel · MerchantDetailModel ·
  │          CommunitiesModel · MerchantAlertsModel · SubmissionModel · SettingsModel
  │          (@MainActor @Observable, small, one job each)
  │
Domain       Merchant · MerchantSummary · Community · PaymentMethods · OpeningHours ·
  │          MapItem · Route   (Sendable value types, no framework imports beyond CoreLocation)
  │
Data         MerchantStore (actor, SQLite + R-tree + FTS5) · SyncEngine (actor) ·
             BTCMapClient (v4) · CommunityClient · AlertsService (CloudKit) ·
             LocationService · CityIndexStore (actor, exists today)
```

Nothing below a layer knows about the layer above. Views never touch the store; models never touch map views.

---

## 1. Performance budgets (why the architecture looks like this)

These budgets come straight from the interactions in `ui-redesign.md` section 5. They are measured with `os_signpost` intervals and enforced by performance tests (section 12).

| UI moment | Budget (p95, iPhone 13-class) | Architectural consequence |
| --- | --- | --- |
| Cold launch to first pins on screen (cached data) | ≤ 400 ms | No full-catalog decode. Read only the viewport from SQLite |
| Camera settles → pins/clusters updated | ≤ 16 ms query + ≤ 8 ms clustering, off main | R-tree query + clustering on a background executor; main thread only applies a diff |
| Tap pin → card content | ≤ 1 frame for summary, ≤ 50 ms for full row | Summary already in memory from the viewport query; full merchant is a primary-key read |
| Keystroke → search results | ≤ 30 ms, no animation | FTS5 prefix query, top 200 by bm25, distance re-rank in Swift |
| Card swipe to next merchant | 0 ms data wait | `BrowseModel` keeps the ordered ID list; next merchant summary is already loaded |
| Resize / fold / rotate | No reload, no flicker, selected pin stays put at the same zoom | All "where am I" state lives in `AppNavigation` and `MapModel`, never in view `@State`; one persistent map layer (`duo.md` 3) |
| Background sync page | Never blocks UI | Single writer actor, WAL mode, readers unaffected |
| Memory working set | ≤ 60 MB | Only the viewport's summaries + the selected merchant in memory (today: ~20 MB file plus full object graph) |
| Main-thread disk I/O | Zero | Enforced by actor isolation; checked with the Main Thread Checker + `os_signpost` in CI perf tests |

---

## 2. Audit of the current architecture

(Before / After / Why, ordered by impact.)

| Before | After | Why |
| --- | --- | --- |
| `ContentViewModel` (3,026 lines): `NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate, MerchantSearchHost`; ~70 `@Published` properties covering map region, selection, path, sheet padding, sync status, communities, events, alerts digest, deep links, onboarding presentation | Deleted. Responsibilities go to `AppNavigation`, `MapModel`, `BrowseModel`, `SearchModel`, `CommunitiesModel`, `MerchantAlertsModel`, `LocationService`, `SyncEngine` | Any `@Published` change re-evaluates every view observing the object. One god object = whole-app invalidation on every map pan, and no unit can be tested alone |
| `Element` model: v4 records mapped into the v2/OSM shape (`osmJSON.tags.paymentLightning`, `osmJSON.lat`, `v4Metadata`), with heuristics like `isPlaceholderName`, `hasMapRenderableIdentity` | v4-only `Merchant` (typed fields) + `MerchantSummary` for map/list | The UI reads typed facts (`paymentMethods.contains(.lightning)`, `openingHours.status(at:)`), not stringly OSM tags. Placeholder handling happens once, at ingest |
| 20 MB `btcmap_elements_v4.json` fully decoded on cold launch and fully re-encoded on each sync page save | SQLite database (`Application Support/merchants.sqlite`), WAL, incremental upserts | Partial reads by viewport and ID; no 20 MB rewrite per sync. Meets criterion 4 in `docs/merchant-storage-evaluation.md` ("query-shaped product needs"): viewport clustering and FTS search are exactly that |
| `MerchantSpatialIndex` (in-memory grid) + 25-mile annotation cap (`maxDistanceMeters = 25 * 1609.344` in `MapView.swift`) | SQLite R-tree viewport query + `MerchantClusterer` | Zooming out stops making merchants vanish; memory stays flat at any zoom |
| `MerchantSearchEngine` scans documents built per element; `MerchantSearchController` (790 lines) mixes local, remote (`V4SearchQuery`) and debounce logic | FTS5 index + `SearchModel`; remote search only as an explicit "search BTC Map" fallback when local returns nothing | Local FTS over ~30k rows is fast enough to need no debounce; less code, deterministic tests |
| Repository mode `auto`: prefer v4, fall back to v2 (`BTCMapV2Client`, legacy `APIManager`, `elements.json`) | v4 only. v2 merchant code and legacy caches deleted | Two data shapes double every bug surface. Offline resilience now comes from the local database, not from a second API |
| Combine `PassthroughSubject`s (`userLocationSubject`, `visibleElementsSubject`, `mapStoppedMovingSubject`, `centerMapToCoordinateSubject`) driving the map | Observation + `AsyncStream` + direct method calls on `MapModel` (`MapModel.flyTo(_:)`) | Fewer hidden channels; Swift 6 friendly |
| Sheet geometry plumbing (`SheetGeometryModel`, `reportSheetHeight`, `reportSheetMotionSettled`, launch-outlier heuristics) feeding map padding | `AppNavigation.sheetDetent` → `MapModel.obscuredInsets` computed from target detent | Removes the most fragile code path; matches the UI spec's fixed map controls |
| Reverse geocoding (`Geocoder.shared`, `LRUCache` of 1,000 entries, `geocodingCache` saved to disk) to build list-row addresses | v4 `address` + OSM `addr:*` fields parsed into `PostalAddress` at ingest; geocoding only in Add Business | `CLGeocoder` is rate-limited; addresses are already in the data |
| `MerchantAlertsManager.shared` singleton `ObservableObject`, plus `BitLocalAppDelegate` in the same 978-line file | `AlertsService` (CloudKit I/O, actor) + `MerchantAlertsModel` (@MainActor @Observable); app delegate in its own file forwarding notification taps to `AppNavigation.handle(_:)` | Separates I/O from UI state; notification taps become ordinary routes |
| Communities: v2 areas for map polygons, v3 areas for browse, member elements loaded separately; state on `ContentViewModel` | `CommunityStore` (SQLite tables `communities`, `community_members`) + `CommunitiesModel` | One community shape; offline; members resolved by join instead of in-memory sets |
| Swift 5 language mode (`SWIFT_VERSION = 5.0`), `DispatchQueue` cache writes, `ObservableObject` | Swift 6 language mode, strict concurrency, actors, `@Observable` | Data races become compile errors |
| Events code paths spread across `ContentViewModel` (`eventsResults`, `ensureEventsLoaded`) and views behind `FeatureFlags.isEventsUIEnabled` | Out of scope: moved into a quarantined `Events/` folder untouched, not wired to the new navigation model | Keeps the redesign focused; a later events project starts clean |

What is kept (it is good): `CityIndexStore` (already an actor), `PlaceDeepLinkResolver` logic, `SearchTextNormalizer`, `OpeningHours` parsing in `BusinessHours.swift`, the v4 snapshot + incremental sync algorithm and its merge tests, `ReleaseNotes`, `FeatureHints`, the zero-third-party-dependency rule.

---

## 3. Domain model (v4-only)

```swift
public struct MerchantID: Hashable, Sendable, Codable, RawRepresentable { public let rawValue: Int }

/// Light shape used by map, clusters, list rows, cards. ~120 bytes.
public struct MerchantSummary: Identifiable, Hashable, Sendable {
    public let id: MerchantID
    public let coordinate: Coordinate          // lat/lon Doubles, Sendable
    public let displayName: String             // never empty: falls back to category name at ingest
    public let category: MerchantCategory      // from v4 `icon` → enum with SF Symbol + localized name
    public let paymentMethods: PaymentMethods  // OptionSet: .onchain, .lightning, .lightningContactless
    public let boostedUntil: Date?
    public let openingHours: OpeningHours?     // parsed once at ingest
    public let updatedAt: Date
}

/// Full shape for detail. Primary-key read, cached per selection.
public struct Merchant: Identifiable, Hashable, Sendable {
    public let summary: MerchantSummary
    public let address: PostalAddress?
    public let contact: Contact                // phone, website, email
    public let socials: [SocialLink]           // twitter, facebook, instagram, line, telegram
    public let about: String?
    public let imageURL: URL?
    public let requiredAppURL: URL?
    public let verifiedAt: Date?
    public let commentsCount: Int
    public let osmURL: URL?
    public let isHydrated: Bool                // false if only snapshot fields are known
    public var id: MerchantID { summary.id }
}
```

Rules:
- `Hashable`/`Equatable` compare `id` + `updatedAt` so SwiftUI diffing is cheap and correct after a sync.
- Mapping from `V4PlaceRecord` / `V4PlaceSnapshotRecord` lives in one `MerchantMapper` (replaces `V4PlaceToElementMapper`) with the existing mapper tests ported.
- Placeholder names (`isPlaceholderName`) are resolved here: a merchant with no usable name stores `displayName = category.localizedName` and `isHydrated = false`; the detail model hydrates it on open.
- `isATM` becomes `category == .atm`; "hide ATMs" becomes a SQL predicate, not an array filter.
- Time-dependent values (`isBoosted`, `openStatus`) are methods taking `Date`, never stored, so tests are deterministic.

Other domain types: `Community` (id, name, icon URL, bounding box, polygon, merchant count, contact/socials, tip Lightning address, verifiedAt), `MapItem` (`.merchant(MerchantSummary)` / `.cluster(ClusterID, Coordinate, count, sampleCategory)`), `Route` (navigation destinations, section 7), `CitySubscription`/`CityDigest` (kept).

---

## 4. Merchant store: SQLite + R-tree + FTS5

### 4.1 Technology

- System `libsqlite3` through a small in-house wrapper (`SQLiteDatabase`, ~400 lines: open, prepare/bind/step, transactions, migrations). Keeps the zero-dependency rule; no GRDB.
- iOS's bundled SQLite includes the R*Tree and FTS5 modules. A launch-time debug assertion and a unit test check `PRAGMA compile_options` for `ENABLE_RTREE` and `ENABLE_FTS5` so a future OS change fails loudly in CI, not in users' hands.
- File: `Application Support/BitLocal/merchants.sqlite` (excluded from iCloud backup; it is re-downloadable). WAL journal, `synchronous=NORMAL`, `foreign_keys=ON`.
- Concurrency: `actor MerchantStore` owns one write connection; reads use a small pool of read-only connections (WAL allows concurrent readers), so a sync transaction never blocks a viewport query.

### 4.2 Schema (v1)

```sql
CREATE TABLE merchants (
  id              INTEGER PRIMARY KEY,
  lat             REAL NOT NULL,
  lon             REAL NOT NULL,
  name            TEXT NOT NULL,
  category        TEXT NOT NULL,
  payments        INTEGER NOT NULL,       -- PaymentMethods bitmask
  boosted_until   INTEGER,                -- unix seconds
  opening_hours   TEXT,                   -- raw OSM string; parsed in Swift
  address_json    TEXT,
  contact_json    TEXT,
  socials_json    TEXT,
  about           TEXT,
  image_url       TEXT,
  required_app    TEXT,
  verified_at     INTEGER,
  comments_count  INTEGER NOT NULL DEFAULT 0,
  osm_url         TEXT,
  is_hydrated     INTEGER NOT NULL DEFAULT 0,
  updated_at      INTEGER NOT NULL
);
CREATE INDEX merchants_category ON merchants(category);

CREATE VIRTUAL TABLE merchants_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);

CREATE VIRTUAL TABLE merchants_fts USING fts5(
  name, category_terms, address, brand,
  content='', tokenize='unicode61 remove_diacritics 2', prefix='2 3'
);  -- contentless; rowid = merchants.id; kept in sync by the store in the same transaction

CREATE TABLE communities (...);           -- id, name, icon_url, bbox, polygon_geojson, merchant_count, details_json, updated_at
CREATE VIRTUAL TABLE communities_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
CREATE TABLE community_members (community_id INTEGER, merchant_id INTEGER, PRIMARY KEY (community_id, merchant_id));

CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);   -- anchors, last success, schema/source versions
CREATE TABLE recent_searches (query TEXT PRIMARY KEY, used_at INTEGER NOT NULL);
```

`category_terms` holds the category's localized names and synonyms (from `ElementCategorySymbols` / the normalizer's category groups) so "coffee", "café" and "espresso" all hit coffee shops. Migrations are numbered and applied in order using `PRAGMA user_version`.

### 4.3 Store API

```swift
public actor MerchantStore {
    func summaries(in rect: GeoRect, filter: MerchantFilter, limit: Int) async throws -> [MerchantSummary]
    func merchant(_ id: MerchantID) async throws -> Merchant?
    func search(_ query: SearchQuery, near: Coordinate?, limit: Int) async throws -> [SearchHit]
    func nearest(to: Coordinate, filter: MerchantFilter, limit: Int, offset: Int) async throws -> [MerchantSummary]
    func categoryCounts(in rect: GeoRect) async throws -> [(MerchantCategory, Int)]
    func apply(_ batch: SyncBatch) async throws -> StoreChange          // upserts + deletes, one transaction
    var changes: AsyncStream<StoreChange> { get }                       // revision + affected bbox
}
```

- `summaries(in:)` splits rects crossing the antimeridian into two R-tree queries.
- `nearest` uses an expanding R-tree box (start ~2 km, double until `limit` rows) and sorts by haversine in Swift; this powers the list (`ui-redesign.md` 6.4) and infinite scroll.
- `search` runs `MATCH` with a prefix query built by `SearchTextNormalizer`, ranks with `bm25(merchants_fts, 10.0, 4.0, 2.0, 3.0)` (name weighted highest), takes the top 200 and re-ranks in Swift by `relevance × distance decay`. Category-only queries short-circuit to a `category IN (...)` filter.
- `MerchantFilter` covers category, payment method, "open now" (evaluated in Swift on the candidate set), and hide-ATMs.

### 4.4 Migration from today's JSON cache

On first launch of the new version:
1. If `Caches/btcmap_elements_v4.json` exists, `SyncEngine` imports it in a single background transaction through `MerchantMapper` (~25k rows; budget < 1.5 s on device, UI shows the cached map as soon as the first 2,000 rows nearest the last viewport commit), then copies the incremental anchor from `btcmap_v4_sync_state.json`.
2. On success, delete the JSON cache, the legacy v2 `elements.json`, and the geocoding cache file.
3. On failure, delete the partial database and bootstrap from the CDN snapshot (current fallback path).
The import is idempotent (upsert by id) so a crash mid-import just restarts it.

---

## 5. Sync engine (v4 only)

`actor SyncEngine` owns all network → store writes.

| Phase | Source | Writes |
| --- | --- | --- |
| Bootstrap (empty DB) | CDN snapshot `api/v4/places.json` (~2 MB, ~29k thin records: id, lat, lon, icon) | Thin rows (`is_hydrated = 0`, name = category fallback). Map is usable immediately |
| Incremental | v4 places `updated_since` paging (existing algorithm and tests) | Upserts + deletes per page in one transaction each; anchor stored in the same transaction |
| Hydration on demand | `fetchPlace(id:)` when a merchant is opened or appears in a card | Full row, `is_hydrated = 1` |
| Background name backfill | Low-priority task hydrating thin rows in the current and recent viewports | Batched upserts |
| Communities | Community areas endpoint(s) (v2/v3 areas today; switch to v4 when BTC Map exposes them) behind `CommunityClient` | `communities`, `communities_rtree`, `community_members` |

- Triggers: app foreground (if last success > 15 min), `BGAppRefreshTask` (registered identifier, ~daily), pull-to-refresh in the list.
- Every applied batch publishes a `StoreChange` (revision + bbox). `MapModel` re-queries only if the bbox intersects the visible rect; `MerchantDetailModel` refreshes only if its id changed.
- Status (`.idle`, `.syncing(progress)`, `.offline(lastSuccess)`, `.failed(UserFacingError)`) is exposed as an `@Observable` `SyncStatus` that the UI shows as the quiet footer line from `ui-redesign.md` 6.1.
- Networking: one `BTCMapClient` (v4) using `URLSession` async APIs, typed decoding, request metadata kept from `BTCMapRequestMetadata`. The v2 `APIManager`, `BTCMapV2Client` (merchants) and repository "auto" mode are deleted (approved 2026-11-08).

---

## 6. Map: viewport queries and clustering

```
camera idle (debounce 150 ms)
   → MapModel.visibleRect (+25% margin), zoom, obscuredInsets
   → Task { store.summaries(in:filter:limit: 5_000) }      // R-tree, background
   → MerchantClusterer.cluster(summaries, zoom, cellSize: 60pt)   // @concurrent, pure Swift
   → [MapItem] diff by stable id
   → MapModel publishes [MapItem]; SwiftUI Map diffs annotations by id (main)
```

- **Map view:** SwiftUI `Map(position:selection:)` with `Annotation` content built from `[MapItem]`. Because BitLocal clusters in its own code, the map never holds more than a few hundred annotations, and that bounded count is what makes SwiftUI `Map` viable.
  - Camera: `MapCameraPosition` stored in `MapModel.camera`. Camera changes come from `onMapCameraChange(frequency: .onEnd)`. Long-press-to-add uses `MapReader` to convert coordinates.
  - Obscured areas (sheet, sidebar, fold) are applied with `.safeAreaPadding`, so camera framing targets the unobscured rect.
  - Keeping camera state as a value in `MapModel` is also what lets it survive folding on iPhone Duo (`duo.md` section 3).
  - This replaces the current `MapView.swift` (793 lines, an `MKMapView` bridge) and its delegate role on `ContentViewModel`.
  - Fallback: if the section 1 performance tests fail with SwiftUI `Map`, a thin `MKMapView` representable renders the same `[MapItem]` with the same `MapModel` API. Features don't change.
- **Clusterer:** grid clustering in projected map points at the current zoom; cluster ID = hash(zoom bucket, cell x, cell y) so clusters are stable while panning (no flicker). Members carry a representative category for the bubble glyph. Co-located members (same coordinate, max zoom) produce a `.cluster` whose tap opens the "N places here" card.
- **Cancellation:** each camera change cancels the previous query/cluster task; only the latest result is applied (no out-of-order pin flashes).
- **Filters:** category chip, payment filters, hide-ATMs and Communities mode dimming are `MerchantFilter` inputs, so pins and list always agree.
- **Selection:** the selected merchant is always rendered as an individual annotation even if it would be clustered, so the selected-pin state from the UI spec is never swallowed by a cluster.
- **Budget check:** the 30k-merchant fixture must cluster a whole-country viewport within the section 1 budget; this is a performance test.

---

## 7. Navigation model

The single owner of "what is shown where" (UI spec 4.2 shows the field list and the per-width rendering table). Architectural rules:

```swift
@MainActor @Observable
final class AppNavigation {
    private(set) var selection: Selection?          // .merchant(MerchantID) | .community(CommunityID)
    var mode: BrowseMode = .places
    var sheetDetent: SheetDetent = .peek
    var lastCompactDetent: SheetDetent = .peek      // restored when folding back to compact
    var path: [Route] = []                          // one path, rendered by sheet / sidebar / fold panel alike
    var isSearching = false
    var modal: Modal?
    private(set) var posture: LayoutPosture = .compact(shortHeight: false)   // duo.md 7.2

    func updateGeometry(_ snapshot: GeometrySnapshot)  // resolves posture; re-homes path; no animation

    func select(_ selection: Selection?, source: SelectionSource)
    func handle(_ url: URL) async                   // universal links + bitlocal:// + notification payloads
    func handle(_ notification: UNNotificationResponse) async
    var restorationState: NavigationState { get }   // Codable, saved with @SceneStorage
    func restore(_ state: NavigationState)
}

enum Route: Hashable, Codable { case merchant(MerchantID), community(CommunityID), allReviews(MerchantID), alerts, settings, addBusiness(prefill: Coordinate?) }
```

- **Selection is an ID, never a model object.** Views resolve IDs through feature models, so a sync that updates the merchant never leaves a stale copy on screen.
- **Selection side effects** (camera move if the pin is outside the unobscured rect, detent change, inspector open, sidebar push) are computed in `select(_:source:)` from `(selection, posture, source)` in one pure function `NavigationReducer.effects(...)` that is unit-tested exhaustively. This is the code that makes resizing/folding "invisible".
- **Deep links:** `PlaceDeepLinkResolver` is kept as the parser; resolution order is local store → `fetchPlace` → "unavailable" route. Merchant-alert notification taps route to `.merchant` or a digest list. Universal links and `NSUserActivity` both funnel into `handle(_:)`.
- **State restoration:** `NavigationState` (selection, mode, detent, query, sidebar path) is saved per scene, so iPad multi-window and app relaunch restore exactly.
- **Multiple windows (iPad):** one `AppNavigation` per scene; stores and services are shared app-wide.

---

## 8. Feature models

All `@MainActor @Observable final class`, created by the app's composition root and injected with `.environment(model)`. Each depends only on services/stores, never on another feature model, except through `AppNavigation`.

| Model | Owns | Depends on | Replaces |
| --- | --- | --- | --- |
| `MapModel` | camera, visible rect, `[MapItem]`, map style, obscured insets, "search this area" flag | `MerchantStore`, `AppNavigation` (read selection), `LocationService` | Map parts of `ContentViewModel`, `MapView` coordinator logic, sheet geometry |
| `BrowseModel` | ordered nearby list (IDs + summaries), paging, featured section, list focus ("near you" vs "near map center"), next/previous for card paging | `MerchantStore`, `MapModel` (rect), `LocationService` | List sorting and `visibleElements` in `ContentViewModel` |
| `SearchModel` | query, scope, sections (places / categories / areas), recents, active category token | `MerchantStore`, `CityIndexStore`, `BTCMapClient` (remote fallback) | `MerchantSearchController`, `MerchantSearchEngine`, `MerchantSearchPersistence` |
| `MerchantDetailModel` | one merchant (created per selection), comments, verification, hydration, translation state | `MerchantStore`, `SyncEngine`, `BTCMapClient` | `ElementCellViewModel`, detail-section fetches |
| `CommunitiesModel` | community list in viewport, selected community, members, tip flow | `CommunityStore`, `MerchantStore` | Communities state in `ContentViewModel`, `CommunityAreasLoader` UI usage |
| `MerchantAlertsModel` | subscription, notification permission, latest digest | `AlertsService`, `LocationService`, `CityIndexStore` | `MerchantAlertsManager` UI state |
| `SubmissionModel` | 5-step draft, validation, autosave, submit | `SubmissionService`, `LocationService`, geocoder | `BusinessSubmissionViewModel` |
| `OnboardingModel` | step, permission results | `LocationService`, `MerchantAlertsModel` | onboarding `@AppStorage` + view logic |
| `SettingsModel` | map style, appearance, units, hide ATMs | `UserDefaults` via a typed `Preferences` | `AppearanceManager`, scattered `@AppStorage` |

Services (non-UI): `LocationService` (actor-backed; `CLLocationUpdate.liveUpdates()` + `CLServiceSession` for authorization, iOS 18+), `AlertsService` (CloudKit), `SubmissionService`, `Preferences`, `SyncEngine`, `MerchantStore`, `CommunityStore`, `CityIndexStore`.

Composition root:

```swift
@main struct BitLocalApp: App {
    @State private var env = AppEnvironment.live()     // stores, services; one per process
    var body: some Scene {
        WindowGroup { SceneRoot(env: env) }             // creates AppNavigation + feature models per scene
    }
}
```

`AppEnvironment.preview()` and `.test()` provide in-memory SQLite and fake clients for previews and tests.

---

## 9. Swift 6 concurrency

- App target: Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (approachable concurrency) so UI code is main-actor by default; the data package is `nonisolated` by default with explicit actors.
- Actors: `MerchantStore`, `CommunityStore`, `SyncEngine`, `AlertsService`, `CityIndexStore`. Heavy pure work (clustering, mapping, opening-hours parsing) is `@concurrent` / `nonisolated` functions on `Sendable` values.
- All domain types `Sendable`. No `@unchecked Sendable` except the SQLite statement wrapper, documented and confined to the actor.
- No Combine, no `DispatchQueue`, no completion handlers in new code. Long-lived tasks are owned by models and cancelled in `deinit`/on scene disconnect.
- Map callbacks (`onMapCameraChange`, selection) are main-actor and call `MapModel` synchronously. Geometry snapshots for posture detection come from `onGeometryChange` with a `nonisolated` `@Sendable` transform (`duo.md` 7.2).

---

## 10. Project structure

```
BitLocal.xcodeproj           app target (thin): composition root, SceneRoot, AdaptiveRootView
Packages/BitLocalKit/        local Swift package, zero dependencies
  Sources/Domain/            Merchant, Community, PaymentMethods, OpeningHours, Route, MapItem
  Sources/Data/              SQLiteDatabase, MerchantStore, CommunityStore, SyncEngine, BTCMapClient, MerchantMapper, Migrations
  Sources/Features/          feature models + views (Map, Browse, Search, MerchantDetail, Communities, Alerts, Submission, Onboarding, Settings)
  Sources/DesignSystem/      BrandColor, Motion, LayoutMetrics, PaymentChips, MerchantCard, GlassControls
  Tests/DomainTests, DataTests, FeatureTests
Events/                      quarantined, unchanged, not in the new navigation graph (out of scope)
```

Why a local package: `Domain` and `Data` tests run on macOS in seconds without a simulator; module boundaries enforce the dependency direction at compile time.

---

## 11. Errors, logging, observability

- Typed errors per layer (`StoreError`, `SyncError`, `ClientError`) mapped once to `UserFacingError` with friendly copy and a recovery action ("Try again", "Open Settings"). Views never show raw error text.
- `os.Logger` subsystems per layer (`sync`, `store`, `map`, `search`, `navigation`) replacing `Debug.log*` and `LogManager`; privacy annotations on any user data.
- `OSSignposter` intervals around viewport query, clustering, search, import, and each sync page; these feed the performance tests and Instruments.
- Telemetry stays as decided in `docs/telemetry-decision.md` (no new third-party analytics).

---

## 12. Testing and verification

| Layer | Tests |
| --- | --- |
| Domain | Swift Testing: mapper (port `V4PlaceToElementMapperTests`), opening hours, payment parsing, category synonyms, boost/open status at fixed dates |
| Data | In-memory SQLite: migrations, R-tree queries incl. antimeridian, FTS ranking (port `MerchantSearchBehaviorTests` expectations), upsert/delete/merge (port `BTCMapMergeTests`, `BTCMapV4SyncTests`), JSON-cache import, `compile_options` check |
| Clustering | Deterministic fixtures; stable cluster IDs across small pans; selected merchant never clustered |
| Navigation | `NavigationReducer` table tests: every (selection × posture × source) combination; `resolvePosture` table; `updateGeometry(_:)` fold/resize round-trips (`duo.md` 8.1); deep-link routing (port `PlaceDeepLinkResolverTests`); restoration encode/decode |
| Feature models | Fake stores/clients; search sections, browse paging, alerts states |
| UI | Snapshot tests per width class and accessibility setting (UI spec section 8); Maestro flows extended (onboarding, select pin → card → directions, search, add business, resize on iPad) |
| Performance | `XCTMetric`/signpost tests on a 30k-merchant fixture for every budget in section 1; fail CI on regression > 20% |

CI: the existing `Build` workflow keeps running build + unit tests; add the package tests (macOS, fast) and the performance suite on `main` nightly.

---

## 13. Migration plan (strangler, every phase ships)

Matches the UI build order in `ui-redesign.md` section 10.

| Phase | Architecture work | UI that becomes possible | Removed |
| --- | --- | --- | --- |
| 1. Foundations | Create `BitLocalKit` package; `Domain` types + `MerchantMapper`; `Element → MerchantSummary` adapter so old views can read new types; Swift 6 mode in the package; CI moves from Xcode 26.3 to Xcode 27.1 (needed for iPhone Duo's full display and vertical bars) | Design tokens (UI step 1) | — |
| 2. Store | `SQLiteDatabase`, `MerchantStore`, migrations, JSON import; `SyncEngine` writes to SQLite; old in-memory path reads from store via adapter (dual-run behind a debug flag, compare counts) | Faster cold launch | JSON cache write path |
| 3. Navigation | First a spike of the persistent map layer under transparent containers (`duo.md` 3.3). Then `AppNavigation`, `NavigationReducer`, `AdaptiveRootView` with `resolvePosture` (incl. Duo fold layouts), scene restoration; `ContentViewModel` delegates selection/path/deep links to it | One width-driven layout, no header, fixed map controls (UI step 2) | `IPhoneLayoutView`, `IPadLayoutView`, sheet geometry plumbing |
| 4. Map | `MapModel`, viewport queries, `MerchantClusterer`, new map coordinator | Pins, clusters, no 25-mile cap (UI step 3) | `MerchantSpatialIndex`, annotation cap, map delegate on `ContentViewModel` |
| 5. Browse + detail | `BrowseModel`, `MerchantDetailModel`, hydration on demand | Merchant card, card paging, reordered detail (UI step 4) | `ElementCellViewModel`, reverse geocoding for rows |
| 6. Search | FTS5 + `SearchModel` | Sectioned instant search (UI step 5) | `MerchantSearchController`, `MerchantSearchEngine`, `MerchantSearchPersistence` |
| 7. Communities, alerts, submission, onboarding, settings | Remaining feature models, `CommunityStore`, `AlertsService`, `LocationService`, `Preferences` | UI steps 6–8 | `ContentViewModel` (deleted), `MerchantAlertsManager.shared`, `AppearanceManager` |
| 8. Cleanup | App target to Swift 6 mode; delete `Element`, v2/v3 merchant clients, `APIManager`, legacy caches, Combine; quarantine Events | Accessibility + perf matrix (UI step 9) | All legacy merchant code |

Each phase ends with the full test suite green, the Maestro flows passing, and before/after screenshots.

---

## 14. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| SQLite module availability changes on a future iOS | `compile_options` test in CI; FTS5 and R-tree are used through the store API only, so a fallback (in-memory grid + scan) could be swapped in without touching features |
| JSON import fails or is slow on old devices | Idempotent background import, nearest-first commit, CDN bootstrap fallback; measured in the perf suite on the oldest supported device class |
| Dropping v2 fallback while v4 has an outage | The local database keeps the app fully usable offline; sync retries with backoff; status line explains "Showing saved places" |
| FTS5 `unicode61` tokenizer is weak for CJK names | Add a secondary `trigram` FTS table for queries containing CJK characters (SQLite ≥ 3.34; iOS 18 ships newer) |
| Big-bang risk of deleting `ContentViewModel` | Strangler phases; adapter layer keeps old views working until each feature model lands |
| Communities API still split across v2/v3 | Hidden behind `CommunityClient`; store shape is version-agnostic |
| Scope creep into Events | Explicitly quarantined; no navigation routes, no store tables |

---

## 15. Product decisions (approved by Joe, 2026-11-08)

Nothing here changes what users see beyond `ui-redesign.md` section 11 (all six approved the same day).
1. **The BTC Map v2 fallback is removed (decided).** v4 is the only merchant source. If BTC Map's v4 service goes down, the app keeps working from the local database instead of switching to the old service (sections 2, 5, 13 phase 8).
2. **First launch after the update** spends about a second moving saved places into the new database in the background; the map is usable the whole time. *No action needed; noting it so it's not a surprise in TestFlight.*
