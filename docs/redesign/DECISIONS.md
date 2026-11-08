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

## Phase 5: merchant card and swipe between places

35. **The card is the first section of the existing detail view**, not a separate sheet state. Compact `card`, full detail, sidebar push and inspector all show it, as the spec asks ("top of every detail"). Dragging the sheet up reveals the rest of the same list.
36. **Paging follows the list order on screen** (`listElementsForCurrentDisplay`: nearest first, or search results while searching). Swiping replaces the detail with the next merchant and selects its pin; the haptic is `.selection`. A rubber band past either end (offset × 0.3). The paging rules live in `CardPaging` (BitLocalNavigation) with tests. VoiceOver gets "Next place" / "Previous place" actions.
37. **Opening hours are parsed in the domain** (`OpeningHours`): the common weekly forms, overnight ranges and `PH off`. Anything richer (dates, comments, `+`, `||`) returns nil and the card leaves out the status instead of guessing. The detail's hours row keeps the existing view until phase 8 removes the old parser.
38. **Action row:** Directions (primary, `brandFill`), Call, Website, Share. Missing actions are left out. Share moved from the toolbar into the row. The overflow menu (copy address, open in BTC Map, report) comes with the detail model in phase 7/8.
39. **Payment chips replace the "Payment details" section.** The "Featured" tag sits next to the name instead of on the first section header.
40. **The embedded map preview is removed** from detail (approved decision 5). A "Show on map" button for the compact `full` detent comes with the detent-aware detail in phase 8.
41. **The detail still reads the legacy `Element`** (through `Element.merchant` for the card). Switching detail to `MerchantStore` + on-demand hydration needs the selection to carry a `MerchantID` end to end, which lands with search (phase 6) when the list also comes from the store.
42. **No inline title yet.** The navigation bar keeps the merchant name; the scroll-driven title waits for the phase 8 polish pass.

## Phase 6: search on the store

43. **Local search now runs on the store's FTS5 index over the whole catalog,** not on the merchants on screen. Every word is a prefix term, accents are ignored, results swap on each keystroke with no debounce (the previous query is cancelled). The remote BTC Map search stays as a top-up for places the local copy doesn't have yet, unchanged.
44. **Ranking:** name matches first, then distance from the map center, then bm25. FTS returns up to 5,000 candidates so a common word like "coffee" still finds the nearest ones; the list keeps the top 200.
45. **Panning no longer narrows store results to the viewport.** The old path re-filtered on every pan; with whole-catalog results that would throw matches away.
46. **The legacy viewport filter (`MerchantSearchEngine`) stays as the fallback** until the store is ready on first launch, and for the existing unit tests, which inject their own repository. It's deleted with `Element` in phase 8.
47. **Category chips still search by category words** (the FTS `category_terms` column, filled from the app's category catalog) instead of applying a hard category filter. The token-in-the-field UI and pin filtering come with the sectioned search screen.
48. **The sectioned search screen (Places / Categories / Areas) and recent searches are not built yet.** The store API for recents (`recordRecentSearch`, `recentSearches`, `deleteRecentSearch`) is in place with tests; the UI is part of the phase 8 pass, after Joe has seen the card and map on a device.

## Phase 7: onboarding, settings, alerts, communities switch

49. **Phase 7 ships the screens; the model split moves to phase 8.** This PR is the visible part (onboarding, settings, alerts, the communities switch, add business). `CommunityStore`, `AlertsService`, `LocationService`, `Preferences`, removing `MerchantSpatialIndex` and deleting `ContentViewModel` all pull on the same `ContentViewModel` state as deleting `Element`, so they land together in phase 8. Without a local compiler, smaller PRs are safer.
50. **Onboarding is 3 steps on a card over the live map** (approved decision 4). The map is blurred 20 pt until location is allowed, then clears and flies to the person (the existing first-location centering). Before permission the map shows its default region, not a curated city. The location step notices the answer when the app becomes active again after the system prompt. Finishing or skipping the alerts step ends onboarding; there's no separate "You're ready" page.
51. **On wide layouts the card is a centered 480 pt panel**, same steps.
52. **Settings is one native list.** "Hybrid" is labelled "Satellite" (same map type). The ATM switch moved into the Map section as "Show ATMs" (not in the spec, but people use it). What's New, Privacy Policy, Rate BitLocal (StoreKit's review prompt, so no App Store ID is needed) and the version (long-press copies it) sit in Settings. The "About BitLocal" sheet stays for contact, socials, other apps, refreshing merchants and replaying onboarding. Attribution is the About section footer.
53. **Alerts:** "Turn off" asks for confirmation. When "Choose a city" can't be used, the reason is a footnote under it. Notifications being off is an inline row with "Open Settings". The contextual prompt in the list footer (3+ opens in one city) isn't built yet; it's in the phase 8 polish pass.
54. **Places / Communities is a segmented control** in the sheet header on compact widths and in the sidebar toolbar on wide ones. The map-mode button is gone from the map controls. Community rows and boundary framing are unchanged.
55. **Add business still hands off to BTC Map's add-location form** (today's behavior), restyled. The 5-step in-app flow in ui-redesign 6.7 isn't built: the old in-app form isn't wired to anything and only emails support, while BTC Map's form is where new places actually get reviewed. **Joe confirmed on 2026-11-08: keep sending people to BTC Map.** The in-app flow and long-press to add are dropped from the plan.
56. **Two feature hints:** search and the communities switch. The alerts hint pointed inside Settings and is dropped. The campaign id is unchanged, so people who already saw the hints don't see them again.

## Phase 8: cleanup (in slices)

57. **The BTC Map v2 merchant fallback is gone** (approved decision 7). `BTCMapRepository` only syncs from v4. If the snapshot or the incremental sync fails, the app keeps showing the saved catalog and the next sync retries. The old `btcmap_data_source_mode` debug switch is removed with it. The v2 *areas* client stays because communities still read v2/v3 area endpoints.
58. **Phase 8 ships in slices, smallest risk first.** Deleting `Element`, `APIManager`, `ContentViewModel` and moving the app target to Swift 6 touches nearly every file. With CI as the only compiler, each slice is its own PR so a red build points at one change.
59. **Recent searches show when the search field is focused and empty**: the last 5, newest first, swipe to delete. A search is saved when it is submitted from the keyboard or picked from the list (2+ characters). They live in the merchant database's `recent_searches` table, so they stay on the device.
60. **"Show on map" appears under the merchant card only when the compact sheet is at its full detent.** It drops the sheet to the card detent so the selected pin is visible. Wide layouts always show the map next to detail, so they don't get the button.

### Fixes from the first simulator pass (iPhone 18 Pro, Xcode 27.2)

61. **The map redraws its store pass when the legacy element cache grows.** On a fresh install the store filled before the element cache, so pins and the list stayed empty or stale until relaunch. This goes away entirely when pins stop needing `Element` (phase 8 cleanup).
62. **Detail no longer repeats the name** in the navigation bar, and the card's close button is gone on compact (the back button does the same thing). The hours line wraps to two lines instead of truncating. Payment chips use primary text with a `brandInk` icon for contrast.
63. **List rows keep a gap between a long name and the distance** (the distance never shrinks or truncates).
64. **The peek detent shows only the header and search field.** The reveal band was tuned for the old 84 pt peek and let half a row through.
65. **Search with no results shows a proper empty state** (`ContentUnavailableView`) instead of one gray line.
66. **Onboarding's alerts step offers "Continue" as a primary button when iCloud is unavailable**, since alerts can't be turned on there.
67. **Dark mode keeps a dark label on the orange Directions button.** White on #FC780F is about 2.6:1 and fails WCAG AA; the dark label is about 7:1. Light mode uses the deeper `brandFill` with a white label (approved decision 2).
68. **The app target moves to Swift 6 in two steps.** First, Swift 5 mode with complete concurrency checking, so every data-race problem shows up as a warning in CI without breaking the build. Once those are fixed, `SWIFT_VERSION` flips to 6 and they become errors.
69. **`APIManager`, `BTCMapV2Client` and `LogManager` are deleted.** Nothing read from them after decision 57; they only kept the old v2 cache alive. A one-time cleanup removes `elements.json` and its keys.
70. **Concurrency fixes favor isolation over locks.** View models, the search host and the search controller are `@MainActor`. Network clients and the repository are `@unchecked Sendable` because their state is immutable or confined to a serial queue, and their completions are `@Sendable`. Pagination keeps its state in arguments instead of captured `var`s. Remote search now ranks results on the main actor, which removes a real race on the map's location.
71. **`nonisolated(unsafe)` only where the safety is documented.** `ISO8601DateFormatter` (thread-safe for parsing and formatting), state touched only in `deinit`, and one-shot values handed straight back (a translation session, notification settings, a notification payload). Each use carries a comment saying why.
72. **The app target is now Swift 6.** Decisions 69–71 cleared all 160 warnings that complete checking found, so `SWIFT_VERSION` is 6.0 and the strict-concurrency override is gone (it is the Swift 6 default). The test target stays in Swift 5 mode for now; its mocks are plain classes that don't need to be Sendable.
73. **Accessibility pass (ui-redesign 7).** Each pin's VoiceOver label now reads name, Featured, category, distance, payment methods and open status. The map has a "Places" rotor that steps through the pins and clusters on screen in reading order. The card gets an "Expand details" VoiceOver action beside Next/Previous place.
74. **"Expand details" is an accessibility action, not a visible button.** Sighted users already drag the sheet up or tap a row, and an extra button would crowd the card. VoiceOver users get the action in the actions rotor, next to the paging actions.
75. **Accessibility text sizes restack instead of truncating.** In the card, the distance moves under the name, payment chips stack, and the action row becomes a two-column grid with two-line labels. In list rows, the distance moves under the name and names wrap to three lines. Boosted list rows now show a worded "Featured" tag.
76. **Increase Contrast turns materials solid** (a `legibleSurface` modifier) on the onboarding card, the feature hints, the map buttons, the card's close button and the city picker. Pin strokes are not thickened: `MKMarkerAnnotationView` has no stroke to change, and the marker already sits on a white outline.
77. **The sheet root always hides its navigation bar.** On iOS 26 it used to keep a visible but transparent bar so that content could run under it. That invisible bar sat on top of the header row and swallowed taps on the Places/Communities switch and the gear (final simulator check, iPhone and folded Duo). The root also keeps its top safe area now, so at the full detent the header no longer slides under the status bar.
78. **The card's action row degrades instead of clipping.** It shows labeled buttons when they fit. Otherwise Directions keeps its label and the others drop to icons, which keep their names for VoiceOver. A sideways scroll is the last resort. At accessibility sizes the buttons stack full width and the subtitle puts one fact per line, so no word hyphenates. Payment chips stack when a row doesn't fit.
79. **The sidebar's Places/Communities switch moves from the bar's center to just under the bar, full width.** In a narrow sidebar the centered switch squeezed the wordmark to "bi…".
80. **The map in the split layout ignores only the vertical safe area.** On iOS 26 the sidebar floats over the detail column. A map running under it hid the selected pin and nearby places, and it tinted the glass sidebar teal in dark mode.
81. **Fold stack on the unfolded, upright Duo is still pending.** Fold detection (`FoldGeometry`) needs the iOS 27.1 SDK's division regions, and CI still builds with Xcode 26.4, so the upright Duo shows side-by-side columns for now. The next step is to read the exact API from the Xcode 27.2 SDK on Joe's Mac and add it behind a compiler check.
