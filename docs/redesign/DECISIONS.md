# Redesign build decisions

Joe asked for the redesign to be built autonomously (2026-11-08): make the calls, record them, and he corrects later.
Every judgment call that the specs in this folder don't settle is logged here with the reason, newest phase last.
To overrule one, say which number and what you want instead.

## Phase 1: foundations

1. **Deployment target stays iOS 18.** The specs disagree (`ui-redesign.md` 3.3 has an iOS 18–25 fallback column and `duo.md` 0 says "stays at iOS 18"; an earlier summary said iOS 26). Keeping 18 changes nothing for current users; iOS 26/27.1 APIs go behind `#available`.
2. **One local package, `Packages/BitLocalKit`, with one module per layer** (`BitLocalDomain`, `BitLocalDesign`; `BitLocalData` and feature modules arrive in later phases) instead of separate packages. One product (`BitLocalKit`) linked by the app. Package tests run with `swift test` on macOS in CI, no simulator.
3. **Swift 6 language mode in the package now; the app target stays Swift 5 until phase 8**, as the spec's migration table says.
4. **`MerchantCategory` is a wrapper around the BTC Map v4 `icon` string**, not an enum. The category catalog (`ElementCategorySymbols`, ~1,000 lines with localized labels) stays in the app for now; the domain only needs identity and `isATM`. Moving the catalog into the package needs its strings moved out of the app's string catalog, which is a phase 7/8 job.
5. **`MerchantSummary.name` is never empty and `hasRealName` says whether it is a real name or the category fallback.** The fallback label is supplied by the app (`MerchantMapper.app`) so it stays localized; search must not treat fallback names as name matches (the same rule `Element.displayName` follows today).
6. **`PaymentMethods` gets a fourth flag, `bitcoinUnspecified`**, for places tagged only `payment:bitcoin=yes` / `currency:XBT=yes`. Today's detail screen shows those as "Accepts Bitcoin", and dropping them would hide real merchants' payment info.
7. **Opening hours stay a raw OSM string on `MerchantSummary` in phase 1.** The existing parser in `BusinessHours.swift` is used by the views; it moves into the domain when the detail screen is rebuilt (phase 5).
8. **The two oranges collapse into `#FC780F`** (`AccentColor` and `MarkerColor` assets now match the `BrandColor.brand` token, all sRGB). The hard-coded Featured gold uses `BrandColor.boost`.
9. **Detail rows lose their orange labels now** (icons `.secondary`, labels `.primary`, link values `brandInk`), ahead of the full detail rebuild in phase 5, because it is low-risk polish the spec lists in build step 1.
10. **CI picks Xcode 27.1+ when the runner image has it, otherwise the newest Xcode 26**, and picks the newest plain iPhone simulator instead of a hard-coded name/OS. The Duo-specific APIs (`reservedRegions`, `toolbarVerticalEdge`) can only compile on Xcode 27.1, so they are added once CI shows that toolchain.

## Phase 2: SQLite merchant store

11. **One SQLite connection owned by the `MerchantStore` actor** instead of a writer plus a pool of read-only connections. Simpler and still never on the main thread; sync pages are short transactions. If the viewport-query budget (≤ 16 ms) is missed while a sync page is being written, the read pool is the first fix.
12. **The FTS5 table stores its own text** (a normal FTS5 table) instead of the spec's contentless table. Contentless tables can only delete rows on SQLite 3.43+ with `contentless_delete`, and deletes are needed on every sync. The extra space is a few MB.
13. **Placeholder/category-fallback names are left out of the FTS name column**, so an unhydrated café never matches "Coffee" as a *name* (it still matches through the category terms column).
14. **The JSON cache is still written in phase 2.** The spec removes the JSON write path in this phase, but nothing reads the store until phase 4 moves the map onto it, so removing it now would leave the current UI without data. The store runs next to it (`MerchantStoreBootstrap`): one-time import of the JSON cache with its sync anchor, then its own v4 sync. Debug builds log whether the two row counts match. The JSON path is deleted when the map switches over.
15. **Merge rules match today's `mergeElements`:** a thin snapshot row never replaces a hydrated one; between hydrated rows the newer `updated_at` wins (ties go to the incoming row).
16. **The import marks a row hydrated unless its name is a "BTC Map Place #" placeholder**, so rows the legacy sync never named get re-fetched on demand.
17. **No `BGAppRefreshTask` yet.** Sync runs at launch; foreground and background refresh triggers land with the feature models in phase 7, where app lifecycle moves out of `bitlocalApp`.

## Phase 3: adaptive navigation shell

18. **The persistent-map spike is deferred to phase 4.** Each layout owns its own `MapView` for now, so a posture change rebuilds the map. Phase 4 replaces the map with a `MapModel` owned above the layouts; doing the spike before that model exists would mean building it twice. Camera framing math (`MapFraming`) is in place and tested so the zoom level can be carried across postures then.
19. **Fold detection is a stub.** `GeometryProxy.reservedRegions(kind: .division)` and the toolbar edge APIs need the iOS 27.1 SDK; CI runs Xcode 26.4, so `FoldGeometry.divisions` returns nothing and Duo falls back to the iPad-style regular/expanded postures (duo.md 7). The resolver and its tests already cover `foldColumns`/`foldStack`; turning it on is a one-function change once CI has Xcode 27.1.
20. **Posture comes from size classes and window size, never the device idiom.** iPhone stays portrait-only in the Info.plist for now; `compactLandscape` is resolved and tested but only reachable on iPad slide-over/Stage Manager.
21. **The peek detent is 128 pt** (was 84): it holds the new header row (wordmark + settings) and the search field. The spec's 120 was one line short once the wordmark moved into the sheet.
22. **The card detent is 36% of the window, clamped to 260–380 pt,** until the merchant card exists and can be measured (phase 5).
23. **About moved into Settings** ("About BitLocal" row). With the top bar gone there was no home for the info button.
24. **Map controls sit top-trailing on split layouts too,** as an overlay. Moving them into the map column's toolbar waits for phase 4's map rewrite.
25. **Only the sheet detent is restored across launches.** Restoring the selected merchant needs detail to read from the store (phase 5).
26. **The UIKit sheet-edge reader stays** for now. The map inset is set from the *target* detent once per change (spec 4.3), and the reader only confirms the measured height when motion settles, so the camera no longer chases a drag.

## Phase 4: map from the store, own clustering

27. **The `MKMapView` bridge stays as the renderer for now** (the spec's named fallback). The new `MapModel` drives it: viewport query, clustering and the list all come from the store. Switching the renderer to SwiftUI `Map` needs the performance tests from architecture section 1 on a real device, and the bridge already keeps one map instance across layouts. `MapModel`'s API doesn't change when the renderer does.
28. **Only plain browsing uses the store-backed map.** Search results, merchant-alert digests and community members stay on the legacy element path until search (phase 6) and communities/alerts (phase 7) move over. Those sets are small, so they keep MapKit's built-in clustering.
29. **No 25-mile cap.** The viewport query reads up to 30,000 rows (the whole catalog today) instead of the spec's 5,000, so whole-country clusters count every merchant. If the device budget check fails, the next step is a per-zoom aggregate table, not a lower limit.
30. **Cluster grid is anchored to the world and fixed within a zoom bucket,** so clusters keep their identity while panning. On screen a cell is 60 to 120 pt depending on where the zoom sits in its bucket. From zoom bucket 18 on, only merchants at the same spot are grouped.
31. **Tapping a cluster zooms in 4×** around it. A cluster of merchants at the same spot opens the first one until phase 5 adds the "N places here" card.
32. **The list shows the 200 nearest merchants inside the visible map,** measured from the center of the unobscured map (above the sheet). It used to be everything within 25 miles.
33. **Pins still need the legacy `Element`** to open detail, so a store row without a matching element is skipped. This only happens while the two caches drift during a sync; it goes away when detail reads from the store in phase 5.
34. **`MerchantSpatialIndex` stays until phase 7.** Its only remaining job is community membership, which moves to `CommunityStore` then. The map-delegate role of `ContentViewModel` also goes in phase 7 with the rest of that class.
