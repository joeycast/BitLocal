# BitLocal UI Redesign Spec

Status: approved by Joe 2026-11-08 (design and planning only, no code changed). All visible decisions in section 11 are decided.
Companion: [`architecture-redesign.md`](architecture-redesign.md) (the architecture half of the same redesign; section 9 below is the short version).
Date: 2026-11-08
Source studied: `github.com/joeycast/BitLocal` @ `c0d5210` (fresh clone), plus existing reference screenshots in `~/Developer/BitLocal-pr51-screens/` (before, glass-panel, cards-v2, duo-fold-layout).
Design lens: Emil Kowalski's design-engineering principles (`/emil-design-eng`): unseen details compound, animate only with a purpose, frequency decides motion, fast ease-out for the system responding, springs for anything a finger can interrupt.
Fits the architecture plan: v4-only `Merchant` model, SQLite store with R-tree viewport queries and FTS5 search, map clustering instead of the 25-mile pin cap, one navigation model that owns selection / sheet / inspector / deep links, small `@Observable` feature models, Swift 6. Events stay out of scope (feature flag stays off; no space reserved for them).

---

## 0. One-paragraph summary

BitLocal becomes a map-first app with exactly one surface for content. On narrow widths that surface is a bottom sheet; on wide widths it is a sidebar, plus an inspector for the selected merchant when there is room. Which one you get depends only on the window's width, never on the device type, so iPhone, iPad, iPad Split View / Slide Over / Stage Manager windows, and the folded or unfolded iPhone Duo are all the same layout system at different widths. The top header bar goes away (the map gets that space back), the search field moves to the thumb, tapping a pin shows a compact merchant card that grows into full detail, and Bitcoin orange is reserved for the things that matter: pins, the selected merchant, and the one primary action on each screen.

---

## 1. Audit of the current UI

Required review format (Before / After / Why). Items are ordered by how much the user feels them.

| Before | After | Why |
| --- | --- | --- |
| Full-width `IPhoneHeaderView` bar (info button, "bitlocal" wordmark, settings gear) permanently covers the top of the map | No header bar. Wordmark sits in the sheet/sidebar header; one profile-style settings button in the sheet header; About moves into Settings | Recovers ~100pt of map on every iPhone. Two chrome buttons for rarely used screens do not earn permanent screen space |
| Two separate layouts (`IPhoneLayoutView`, `IPadLayoutView`) picked by device idiom; onboarding picks sizes by `UIDevice.current.userInterfaceIdiom` and hard-coded screen categories | One `AdaptiveRootView` that reads container width and picks `compact` / `regular` / `expanded` | iPad Slide Over, narrow Split View and Stage Manager windows are phone-width; the unfolded Duo is neither phone nor iPad. Width is the only honest signal |
| iPad sidebar: wordmark and the info/settings buttons overlap the "Search merchants…" field (visible in `before/ipad-air11.png`) | Sidebar header is a normal toolbar row: wordmark leading, settings trailing, search field below with its own row | Overlap reads as broken. `sidebarRootTopCompensation = 30` was patching around the iOS 26 nav bar; drop the patch with the header |
| Map control pill (map type, locate, communities) rides up and down with the sheet using `SheetEdgeHeightReader` + launch-outlier heuristics | Controls pinned top-trailing below the status bar on compact; they fade out (opacity only) when the sheet passes the card detent | Matches Apple Maps, removes the most fragile code in the app (live sheet-height tracking), and the controls never fight the sheet during a drag |
| Communities is a map-button toggle (`person.3.fill`) that swaps the whole sheet | Segmented "Places / Communities" control in the sheet/sidebar header | A mode switch belongs next to the content it changes, labeled with words |
| Pins are stock `MKMarkerAnnotationView` balloons with one color, `canShowCallout = true`, cluster tint logic that returns the same color in all three branches | Custom compact pin (category glyph in an orange disc), cluster bubble with count, selected-pin state, boosted ring. Callouts off; selection drives the card | Callouts duplicate the card. Smaller pins show more of the map; a distinct selected state tells you which merchant the card is about |
| 25-mile distance cap on annotations (`maxDistanceMeters = 25 * 1609`) | Viewport R-tree query + clustering at every zoom level | Zooming out currently makes merchants disappear, which reads as "no merchants". Clusters keep the world honest |
| Merchant row: name, distance, street line, city line, payment icons (4 lines, ~110pt tall) | Two-line row: name + distance; category · open status · payment glyphs | Twice as many merchants visible per screen; city is redundant when everything is nearby |
| Detail screen: 9 stacked inset-grouped sections, every label orange ("Address", "Website", "Phone"…), full 7-day hours table, embedded map preview | Hero header + action row + "Pay with" + compact info rows (today's hours, expandable) + reviews + verification footnote + boost. No embedded map on compact; map is already behind the sheet | Orange labels everywhere means nothing stands out. The things people need at the door (open now? which payment? directions) come first |
| Search field in sheet uses `RoundedRectangle(cornerRadius: 40)` on `tertiarySystemFill` with `.animation(.easeInOut(duration: 0.2))` tied to search activation | System `.searchable` field in the sheet header (glass on iOS 26), results replace instantly, no animation on keystrokes | Typing is a 100+ times a day action; never animate it. System field gets Dynamic Type, dictation and scope bars for free |
| Add Business: circular 56pt icon buttons (chevron / arrow / paper plane) in a bottom bar, `NavigationView` | Full-width labeled "Continue" / "Submit" button pinned above the keyboard, back in the nav bar, progress bar on top, `NavigationStack` | An unlabeled paper plane is a guess. A labeled full-width button is the most reachable target on a phone |
| Onboarding: 5 pages, each with a different background color (orange, green, blue, orange, purple) and a big SF Symbol | 3 steps over a live, blurred map: Welcome, Location, Alerts (optional). Single brand palette | Five colors say five different apps. The map itself is the best explanation of what BitLocal does |
| Settings and About are separate popovers on iPad and separate sheets on iPhone | One Settings screen with an About section | Fewer entry points, one place to look |
| Animations: `.easeInOut(duration: 0.25)` on appearance changes, onboarding `iconScale` pulse, generic `easeInOut` everywhere | Named motion tokens (section 5); springs for anything gesture-driven, ease-out for system responses, nothing on keyboard/typing | `easeInOut` delays the first frame; the user is looking hardest at the start |
| Featured section header tint `Color(red: 0.71, green: 0.50, blue: 0.12)` hard-coded; `MarkerColor` (#FF6D00) and `AccentColor` (#FC780F) are two slightly different oranges | One `BrandColor` token set (section 3.2) with light/dark and contrast-safe text variants | Two near-identical oranges look like a mistake side by side |
| Dynamic sheet detents `.fraction(0.3)`, `.medium`, `.large`, plus collapsed; map padding estimates per detent | Three named detents: `peek`, `card`, `full` (section 4.3). Map padding comes from the navigation model, not from measuring the sheet | Fewer, meaningful stops; the card detent is sized to the card's content |

---

## 2. Design principles

1. **The map is the product.** Every pixel of chrome must justify covering the map. Default state: map + one floating search sheet + three small controls.
2. **One content surface per width.** Sheet when narrow, sidebar (+ inspector) when wide. The same screens appear in both; only the container changes.
3. **Answer "can I pay here, and is it open?" in one glance.** Payment methods and open status show on pins' card, list rows and the detail header.
4. **Orange means "this one".** Bitcoin orange marks merchants on the map, the selected merchant, and the single primary action per screen. Everything else is neutral.
5. **Fast where the system responds, unhurried where the user decides.** Selection, search and navigation feel instant. Only rare moments (onboarding, first alert set-up, submission success) get delight.
6. **Invisible correctness.** Selection survives rotation, resizing, folding, and deep links. A window resized from iPad full screen to Slide Over keeps the same merchant open, now in the sheet instead of the inspector. Nobody will notice; that is the point.
7. **Native first.** System sheet, `NavigationSplitView`, `.searchable`, `.inspector`, Liquid Glass on iOS 26. Custom only where BitLocal has something to say (pins, merchant card, payment chips).

---

## 3. Visual language

### 3.1 Typography

- **System font (SF Pro) for all UI**, using text styles only (`.largeTitle` … `.caption2`) so Dynamic Type works everywhere. No fixed point sizes in content.
- **Fredoka Medium** stays for two places only: the "bitlocal" wordmark and onboarding titles. It is brand voice, not UI text.
- Delete unused `Ubuntu-LightItalic` / `Ubuntu-MediumItalic` from the bundle if nothing references them (check at implementation time).
- Numbers that change or sit in columns (distance, hours, cluster counts, review counts) use `.monospacedDigit()` so they don't jitter.
- Hierarchy inside a merchant card: name `.title3.weight(.semibold)`, meta line `.subheadline` secondary, chips `.footnote.weight(.medium)`.
- Line limits: names 2 lines in card/detail, 1 line in list rows (truncate tail). Never `minimumScaleFactor` on names.

### 3.2 Color

Tokens live in one `BrandColor` namespace (asset catalog colors with light/dark variants). Values checked for WCAG contrast:

| Token | Light | Dark | Use | Contrast |
| --- | --- | --- | --- | --- |
| `brand` | #FC780F | #FC780F | Pin fill, selected-pin ring, cluster bubble, progress bar, icons ≥ 20pt | Graphic use only (3:1 non-text rule: 2.7:1 on white is borderline, so pins always get a white 1.5pt stroke + shadow) |
| `brandInk` | #B34D00 | #FF8A1F | Orange *text* and small glyphs (links, "Open" accents, selected chip label) | 5.3:1 on white, 7.2:1 on #1C1C1E |
| `brandFill` | #C25400 | #FC780F | Primary button background | White label on #C25400 = 4.6:1; dark mode uses a near-black label on #FC780F = 7.8:1 |
| `boost` | #B8860B-family gold (tune) | lighter gold | Boosted ring on pins, "Featured" tag | Replaces the hard-coded `Color(red: 0.71, green: 0.50, blue: 0.12)` |
| `open` / `closed` | system green / system red | same | Open-status text, always paired with the word ("Open", "Closes 6 PM") | Never color alone |

Rules:
- `MarkerColor` and `AccentColor` collapse into `brand` (the app accent).
- Neutral surfaces use system semantic colors (`.background`, `.secondarySystemBackground`) so dark mode and Increase Contrast come free.
- The current orange labels on every detail row become `.primary` text with `.secondary` SF Symbols. Orange appears on the row only for the tappable value when it is a link (website, phone) and only in `brandInk`.
- Payment glyphs: on-chain ₿, Lightning ⚡, contactless NFC. Neutral `.secondary` in rows; in the detail "Pay with" block they get labels ("Lightning", "On-chain", "Tap to pay").

> Decided (approved 2026-11-08): primary buttons use the deeper `brandFill` orange in light mode (#C25400 instead of #FC780F) so white button text is readable. Pins and the brand stay the bright orange.

### 3.3 Liquid Glass (iOS 26+) and fallback (iOS 18–25)

Glass is for **floating controls that sit on the map**, not for content.

| Element | iOS 26+ | iOS 18–25 |
| --- | --- | --- |
| Bottom sheet | System sheet (gets glass automatically at the `peek` and `card` detents; opaque at `full`) | System sheet, `.regularMaterial` background at `peek`/`card` |
| Map controls (locate, map style) | `GlassEffectContainer` with `.glassEffect(.regular.interactive(), in: .capsule)`; buttons merge into one capsule | `.regularMaterial` capsule, 0.5pt separator stroke |
| Sidebar / inspector | System `NavigationSplitView` sidebar glass; inspector opaque | System default |
| "Search this area" pill | `.glassEffect(.regular.interactive())` | `.thinMaterial` |
| Merchant card, list rows, detail sections | **Not glass.** Plain sheet background, inset grouped cards | Same |
| Selected chip / segmented control | System controls | System controls |

- Use `glassEffectID` + `@Namespace` so the map-style button morphs into the map-style menu (iOS 26) instead of a popover appearing from nowhere.
- Respect **Reduce Transparency**: glass and materials fall back to solid `secondarySystemBackground` (system does this for glass; do it explicitly for any custom material).
- Never stack glass on glass (e.g. a glass chip inside the glass sheet). Chips inside the sheet use `secondarySystemFill`.

### 3.4 Shape, spacing, iconography

- Spacing scale: 4, 8, 12, 16, 20, 24, 32. Screen-edge margin 16pt (20pt in sidebar/inspector).
- Corner radii: chips/capsules = full capsule; cards inside lists = 16pt continuous; merchant card hero image (if a photo is ever added) = 12pt; nested radius rule: inner = outer − padding.
- SF Symbols only, `.symbolRenderingMode(.hierarchical)` for row icons, weights matched to adjacent text (`.imageScale(.medium)` and text-style fonts instead of `.font(.system(size: 13, weight: .bold))`).
- Hit targets ≥ 44×44pt everywhere, including map controls (currently 46×42) and chips.

---

## 4. Layout system and interaction model

### 4.1 One width-driven layout

`AdaptiveRootView` starts from **size classes** (`horizontalSizeClass == .regular`, never `!= .compact`) and refines with the **container size** (`onGeometryChange` on the root) and, on iOS 27.1+, the **fold geometry** (`reservedRegions(kind: .division)`). Never `UIDevice` idiom, `UIScreen.main` or orientation. The full posture resolution, including the iPhone Duo fold layouts, is in [`duo.md`](duo.md) section 7.

| Width class | Container width | Structure | Typical cases |
| --- | --- | --- | --- |
| `compact` | Compact horizontal size class | Full-bleed map + bottom sheet (short heights < 740pt use the horizontal card row at the `card` detent, see `duo.md` 4) | Every iPhone portrait, iPhone landscape* , iPad Slide Over, iPad 1/3 Split View, small Stage Manager windows, Duo folded (outer display) |
| `regular` | Regular width, < 1000pt, no fold reported | Sidebar (list/search/communities) + map. Merchant detail pushes **inside the sidebar** | iPad portrait 11", iPad 1/2 Split View, medium Stage Manager windows, Duo inner display on iOS < 27.1 |
| `expanded` | Regular width, ≥ 1000pt | Sidebar + map + **inspector** (merchant detail on the trailing edge). Sidebar can be collapsed | iPad landscape, 13" iPad portrait, large Stage Manager windows |
| `foldColumns` / `foldStack` | Regular width + fold (division region) on iOS 27.1+ | Browse column on one side of a vertical fold and map on the other, or map above a horizontal fold and browse panel below. Detail pushes inside the browse container | Duo unfolded sideways / upright, including partly folded poses. See `duo.md` 1–2 |

\* iPhone landscape: width can exceed 600pt but height is ~400pt. Rule: if height < 500pt, use `regular` with a narrower sidebar (320pt) instead of the sheet, because a bottom sheet in a 400pt-tall window leaves no map. This replaces today's separate landscape strip experiments.

Thresholds are constants in one place (`LayoutMetrics`) so they can be tuned after testing.

**Hinge / fold (iPhone Duo):** fully specified in [`duo.md`](duo.md). In short:
- Column edges snap to the fold, and nothing interactive or readable crosses it. Only map tiles may cross.
- Folding and unfolding keep the selection, path, search and map zoom, with no animation and no camera jump.
- Folded Duo is `compact`, but its outer display is wide and short, so the `card` detent becomes a swipeable horizontal card row.
- On Duo the merchant detail always pushes inside the browse container (the inner display is never wide enough for an inspector).

### 4.2 The single navigation model

One `@MainActor @Observable final class AppNavigation` owns everything that decides *what is shown where*. Layout containers read it; they never own selection state.

```swift
@MainActor @Observable
final class AppNavigation {
    var selectedMerchantID: Merchant.ID?          // the one source of truth for selection
    var mode: BrowseMode = .places               // .places | .communities
    var selectedCommunityID: Community.ID?
    var sheetDetent: SheetDetent = .peek          // used only in compact
    var isInspectorPresented: Bool                // derived in expanded: selectedMerchantID != nil
    var path: [Route] = []                        // one path; sheet, sidebar or Duo fold panel renders it
    var lastCompactDetent: SheetDetent = .peek    // restored when folding back to compact
    var modal: Modal?                             // .settings, .addBusiness(prefill), .alerts, .onboarding
    var searchQuery: String = ""
    var isSearching: Bool = false

    func select(_ id: Merchant.ID?, source: SelectionSource)   // map, list, search, deepLink
    func handle(_ url: URL)                                    // place links, alert notifications
    func updateGeometry(_ snapshot: GeometrySnapshot)          // resolves posture (duo.md 7), re-homes selection on resize/fold
}
```

How each layout renders the same state:

| State | compact | regular | expanded |
| --- | --- | --- | --- |
| Nothing selected | Sheet at `peek` (or wherever the user left it) with search + list | Sidebar shows list | Sidebar list, no inspector |
| Merchant selected | Sheet shows merchant card at `card` detent; drag to `full` for detail | Sidebar pushes detail; map centers pin in the visible map area | Inspector opens with detail; sidebar keeps the list with the row highlighted |
| Community selected | Sheet shows community detail; boundary drawn on map | Sidebar pushes community detail | Inspector shows community detail |
| Search active | Sheet goes to `full`, keyboard up | Sidebar shows results | Sidebar shows results; inspector unchanged |
| Deep link to merchant | `select(id, .deepLink)` then same as "Merchant selected"; map flies to it | same | same |

`updateGeometry(_:)` is the invisible detail that makes resizing and folding feel solid (Duo specifics in `duo.md` 3): going from `expanded` to `compact` (e.g. iPad full screen to Slide Over) turns an open inspector into the sheet at `card`; going back opens the inspector again. Scroll position inside detail is preserved per merchant ID.

Feature models stay small and own data, not navigation:
- `MapModel`: camera, viewport, `visibleClusters` (R-tree query on camera idle), map style.
- `SearchModel`: FTS5 query, results grouped, recents, scope.
- `MerchantDetailModel(id:)`: loads one merchant + comments + verification, created per selection.
- `CommunitiesModel`, `MerchantAlertsModel`, `SubmissionModel`, `SettingsModel`.
- All `@MainActor @Observable`; store and network are actors; Swift 6 strict concurrency.

### 4.3 Bottom sheet (compact)

Always present after onboarding; not dismissible (`interactiveDismissDisabled`), background interaction enabled up to `card`.

| Detent | Height | Content |
| --- | --- | --- |
| `peek` | Search field + mode control + 1 line ("23 places nearby") ≈ 120pt + safe area | Map is primary |
| `card` | Fits content: list (≈ 3 rows) or a selected merchant card (header + action row + pay-with) — computed with `.height` from measured card, clamped 260–380pt | Browsing and the selected-merchant card |
| `full` | `.large` | Search, full list, full merchant detail |

Rules:
- The map's bottom inset (`MapModel.bottomInset`) is set from the **target** detent when a detent changes, not from live sheet measurement. The map recenters on the selected pin once, after the sheet settles. This removes `SheetEdgeHeightReader`, `reportSheetMotionSettled`, the launch-outlier logic, and attribution offset hacks.
- OpenStreetMap attribution: moves into the sheet footer (list bottom) and Settings > About, plus a tiny `ⓘ` in the map corner on wide layouts. Attribution requirements are still met; it no longer chases the sheet. (Confirm OSM/BTC Map attribution wording requirements during implementation.)
- Map controls on compact sit top-trailing **inside the safe area**, which keeps them clear of iPhone Duo's outer camera strip (PR #51's collision). On iOS 27.1 they sit on the edge opposite `toolbarVerticalEdge`. When the sheet goes past `card` they fade (opacity 150ms, no movement).

### 4.4 Map, pins and clustering

- **Data:** on camera idle (debounced 150ms), `MapModel` asks the store for merchants in the visible rect plus 25% margin via the R-tree, then clusters. No distance cap.
- **Clustering:** MapKit clustering (`clusteringIdentifier`) is fine for < ~2,000 visible annotations; above that, cluster in the store layer with a grid (screen-space cells ~60pt) and hand MapKit only cluster + single annotations. Cluster bubble shows a count (`.monospacedDigit()`, abbreviated: 1.2k).
- **Pin anatomy:** 28pt orange disc, white 1.5pt stroke, category glyph in white, soft shadow. Boosted: 2pt gold outer ring. Selected: grows to 36pt with the name label shown below it.
- **Labels:** merchant names show as map labels only at high zoom (MapKit collision handling via `displayPriority`), selected pin always labeled.
- **Tap pin:** select (card appears). **Tap cluster:** zoom to fit its members; if members share a coordinate (same building) or max zoom reached, show a "4 places here" list in the card.
- **Tap empty map:** deselect, sheet returns to its previous detent.
- **Long-press map:** drops a temporary pin and offers "Add a business here" (prefills Add Business location step). Haptic `.impact(.medium)` at the moment the pin drops.
- **"Search this area" pill:** appears top-center when the camera moved far from the area the current search/list was computed for, after the map settles. Tapping re-runs. Fades in 150ms.
- **Empty viewport:** inline card text "No places in this area yet" with "Zoom out" and "Add a business" actions.
- **Map style control:** one button opens a small menu: Standard / Satellite (hybrid). On iOS 26 it morphs from the glass button.
- **Locate button:** centers on user; second tap toggles heading mode (system `MapUserLocationButton` behavior). If location is off, shows a short explanation and a Settings deep link.
- **Communities mode:** community boundaries drawn as polygons (brand stroke 2pt, 8% fill), centroid labels; merchant pins dimmed to 40% but still tappable.

### 4.5 Merchant card (compact `card` detent, and top of every detail)

```
┌──────────────────────────────────────────┐
│  Prickly Pear Coffee Co.          0.3 mi │  title3 semibold / monospaced distance
│  Coffee shop · Open · Closes 6 PM        │  subheadline secondary, "Open" in green
│  ⚡ Lightning   ₿ On-chain                │  chips
│ ┌──────────┐ ┌────┐ ┌────────┐ ┌──────┐  │
│ │Directions│ │Call│ │Website │ │Share │  │  action row, Directions = primary
│ └──────────┘ └────┘ └────────┘ └──────┘  │
└──────────────────────────────────────────┘
```

- Directions opens Apple Maps (and offers Google Maps if installed, via a long-press menu).
- Actions not available for a merchant are omitted (row reflows), never disabled.
- **Swiping horizontally on the card pages to the next/previous merchant** in the current list order (nearest first). The map pin selection follows. Spring, interruptible; velocity flick > 0.11 pt/ms pages even below the distance threshold. This turns "browse what's around me" into one thumb motion.
- Dragging the card up continues into full detail (same view, more sections revealed), not a navigation push. Back from full detail = drag down or the close button.
- Close button (xmark, 30pt glass circle, 44pt hit area) top-trailing deselects.

### 4.6 Sidebar and inspector (regular / expanded)

- `NavigationSplitView` with `navigationSplitViewColumnWidth(min: 320, ideal: 360)` and **no max** (in a fold-aligned pose the system can widen the sidebar to the fold). The map is the persistent layer under the transparent detail column (`duo.md` 3.3).
- Map controls in regular/expanded are system `ToolbarItem`s on the map column with text + SF Symbol, so they join iPhone Duo's vertical bar on iOS 27.1. Floating glass controls are used only in compact layouts.
- Sidebar header: "bitlocal" wordmark leading, settings button trailing, search field below, Places/Communities segmented control, category chips.
- `regular`: selecting a merchant pushes `MerchantDetailView` onto the sidebar stack (back button returns to the list with scroll position kept).
- `expanded`: `.inspector(isPresented:)` 340–420pt on the trailing edge shows `MerchantDetailView`; the list stays visible with the selected row highlighted (`brand` 12% fill, no animation on keyboard arrow navigation).
- Keyboard (iPad with keyboard): `⌘F` focuses search, `↑/↓` moves selection in the list (map follows, **no animation**), `Esc` deselects, `⌘,` Settings, `⌘N` Add Business. These are high-frequency; they never animate.
- Pointer: rows and map controls get `.hoverEffect(.highlight)`; pins get a subtle lift on hover (gated to pointer devices).

---

## 5. Motion and gesture spec

Frequency decides everything (Emil's rule). Tokens live in `Motion.swift`:

```swift
enum Motion {
    static let press      = Animation.spring(duration: 0.16, bounce: 0)         // button press-down feedback
    static let respond    = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20) // strong ease-out: system responding
    static let move       = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.28) // on-screen movement
    static let select     = Animation.spring(duration: 0.30, bounce: 0.15)       // pin select, card paging
    static let gesture    = Animation.interactiveSpring(duration: 0.30, extraBounce: 0) // drag follow
    static let delight    = Animation.spring(duration: 0.50, bounce: 0.25)       // rare moments only
}
```

| Interaction | Frequency | Animation | Notes |
| --- | --- | --- | --- |
| Typing in search, results updating | 100+/day | **None** | Results swap instantly. No row insert animations while typing |
| Keyboard list navigation (iPad) | 100+/day | **None** | Selection highlight and map pan jump |
| Tap pin → select | Tens/day | `select` spring: pin 28→36pt, label fades in; card content crossfade 180ms with 2pt blur on the outgoing content | Blur hides the double-image during crossfade between two merchants |
| Card horizontal paging | Tens/day | `gesture` while dragging, `select` on release, retargetable | Rubber-band at first/last merchant (damping: offset × 0.3) instead of a hard stop |
| Sheet detent changes | Tens/day | System sheet animation | Don't override |
| Map camera to selected merchant | Tens/day | MapKit camera animation, only if pin is outside the visible (un-covered) map rect | Don't move the map if the pin is already visible; moving the world on every tap is disorienting |
| Button press (custom buttons, chips, action row) | Tens/day | Scale 0.97 with `press`; release `respond` | System buttons keep system feedback |
| Map controls fade with sheet | Tens/day | Opacity only, 150ms ease-out | No movement |
| Search this area pill | Few/day | Fade + 4pt rise, `respond` 200ms; exit 120ms fade | Exit faster than enter |
| Inspector open/close, sidebar push | Few/day | System | |
| List first load | Once per session | Stagger first 6 rows, 40ms apart, 8pt rise + fade, 240ms | Never re-staggers on refresh or search; never blocks taps |
| Cluster split on zoom | Constant | MapKit default | |
| Merchant alerts "You're set" confirmation | Rare | `delight` spring checkmark + `.success` haptic | |
| Submission success | Rare | `delight`: card scales 0.96→1 with fade, confetti-free orange checkmark | |
| Onboarding page change | Once | `move` 280ms, content slides 24pt + fades; the map behind slowly pans (linear, constant) | |
| Appearance change (light/dark) | Rare | No custom animation; let the system handle it | Remove the `.animation(.easeInOut(0.25), value: appearance)` modifiers |

Never: animate from `scale(0)` (minimum 0.9 + opacity), `easeIn` on anything, durations above 300ms for UI responses, repeating/pulsing animations on idle screens (remove onboarding `iconScale` pulse).

**Haptics:** `.selection` on pin select and card page, `.impact(.medium)` on long-press pin drop, `.success` on alert enabled and business submitted, `.warning` on submission error. No haptics while scrolling or typing.

**Reduce Motion:** pin grow becomes an instant swap + ring; card paging crossfades without slide; onboarding slides become fades; map camera moves become jumps; stagger off. Opacity transitions stay (they help comprehension).

**Gesture details (the invisible ones):**
- Card paging ignores a second finger once a drag starts (no jump).
- Horizontal card swipe only claims the gesture after 10pt of mostly-horizontal travel, so vertical sheet drags never get stolen.
- A tap on a pin while the sheet is mid-drag is honored after the sheet settles, not dropped.
- Deselecting via tapping the map is ignored if the tap ended a map pan.

---

## 6. Screens

### 6.1 Map (home)

Compact: full-bleed map, top-trailing glass controls (locate, map style), sheet at `peek` showing search field, Places/Communities control, and a one-line summary ("23 places nearby" / "Zoom in to see places"). Regular/expanded: sidebar + map (+ inspector).

First launch after onboarding: sheet opens at `card` with the nearest list so people see merchants immediately, then remembers the user's last detent.

Loading (no cache yet): the sheet shows skeleton rows (static, with a slow 1.2s linear shimmer at low contrast) and the copy "Finding bitcoin-friendly places near you". Map pins fade in as the snapshot arrives (one 200ms fade for the batch, not per pin). Offline with cache: a small inline "Showing saved places · Updated 2 days ago" line in the sheet footer, no blocking banner.

### 6.2 Search

- Field: system `.searchable` in the sheet header (compact) / sidebar (wide). Placeholder "Search places, categories, cities".
- Focusing search: compact sheet goes to `full`.
- Empty query: recent searches (max 5, swipe to delete) + category chips (top 6 categories present in the current viewport).
- With query (FTS5, prefix matching, typo-tolerant ranking from the existing normalizer):
  - **Places**: name/category matches, sorted by relevance then distance. Rows show distance.
  - **Categories**: "Coffee shops · 14 nearby" applies a category filter.
  - **Areas**: cities/communities from bundled cities DB; tapping flies the map there.
- Scope: results cover everywhere, sorted nearest-first; a "Near the map" / "Everywhere" scope bar appears only when both have results.
- Applying a category chip shows it as a removable token in the field; the map filters pins to that category (non-matching pins hide; clusters recount).
- Results swap instantly. Single result + Return key selects it.
- No results: "No places match "xyz"" + "Add it to BitLocal" action (prefilled name in Add Business).

### 6.3 Merchant detail

Same view in the sheet (`full`), sidebar push (regular) and inspector (expanded). Order:

1. **Header** (the merchant card from 4.5): name, category · open status · distance, Featured tag if boosted.
2. **Action row:** Directions (primary, `brandFill`), Call, Website, Share. Overflow menu: Copy address, Open in BTC Map, Report an issue.
3. **Pay with:** labeled payment chips; "Required app: Wallet X" inline under it when present.
4. **Info rows** (inset grouped, `.primary` text, `.secondary` icons): Address (tap = copy/directions menu), Hours (today's line: "Open · Closes 6 PM", tap to expand the week; today bold; identical consecutive days merged: "Mon–Sun 10 AM–6 PM"), Phone, Website, Email, Socials as a compact icon row.
5. **About** (description) with the existing on-device Translate action.
6. **Community reviews:** latest 3, "See all (12)" to a list. Translate retained.
7. **Verification:** one footnote line with an icon: "Verified by the community 3 months ago" or "Not yet verified in person".
8. **Boost:** quiet footer card "Feature this merchant on BTC Map" (secondary style, not orange) with the existing disclaimer.
9. **Map preview:** only in contexts where the main map is hidden (compact `full` detent shows a small "Show on map" button instead; the embedded `MapPreviewView` is removed from detail).

Navigation title appears in the bar only after the header scrolls away (inline title on scroll), so the name isn't shown twice.

### 6.4 List (nearby)

- Section "Featured nearby" (boosted, max 3, gold tag) then "Nearby" sorted by distance from the map center (not just the user) once the user has panned; from the user when the map is centered on them. Label says which: "Near you" vs "Near map center".
- Row: 2 lines (4.1 audit). 64pt min height. Selected row highlighted.
- Rows load by viewport via the store; infinite scroll pages of 50 replace "Load more results".
- Swipe actions: Directions (leading), Share (trailing).
- Context menu (long-press): preview of the merchant card + Directions / Copy address / Share.

### 6.5 Communities

- Segmented control switches to Communities; the list shows communities in or near the viewport: icon, name, merchant count (`storefront` glyph + monospaced count), distance.
- Selecting a community: map fits its boundary; detail shows description, merchant list (tap selects merchant → switches mode back to Places with that merchant selected), contact/socials, verification, and the Lightning tip card.
- Tip card: secondary style with ⚡ icon, "Tip this community" button; wallet chooser stays as a confirmation dialog with the existing disclaimer text.
- Search in communities mode filters communities by name.

### 6.6 Merchant alerts

- Entry: Settings > Merchant Alerts, onboarding step 3, and a contextual prompt in the list footer when the user has opened BitLocal 3+ times in the same city without alerts ("Get a morning note when new places open in Nashville").
- Not set up: illustration-free header (SF Symbol `bell.badge` in `brand`), one sentence, "Choose a city" primary button. City picker = searchable list with the current city suggested first (from location), then nearby cities.
- Active: city card with "Daily morning digest" subtitle, "Change city" and "Turn off" (destructive, confirmation). "Latest update" list shows the last digest's merchants; tapping one selects it on the map and closes Settings.
- Notifications off at the OS level: inline warning row with "Open Settings" link (not a blocking alert).
- iCloud unavailable: inline explanation row; the button disabled with the reason as its footnote (this is the one case where disabled-with-reason beats hiding, because the user must understand why).

### 6.7 Add business

Full-screen modal (`fullScreenCover` on compact, large sheet `.presentationSizing(.form)` on wide). `NavigationStack`, progress bar under the nav bar (5 segments, `brand`), Cancel leading, step title centered.

1. **Location:** map with a center-fixed pin; drag the map under it. Search field for address/business lookup above. Pre-filled from long-press or current location. "Use this location" primary button.
2. **Details:** name, category (searchable picker), website, phone, email, description. Inline validation messages under fields (friendly: "That website doesn't look complete yet"), never alerts.
3. **Payments:** three large toggle cards (Lightning, On-chain, Tap to pay), at least one required; "Requires a specific app" optional field.
4. **Hours:** per-day rows with a "Same hours every day" shortcut and "Closed" toggles; skippable.
5. **Review:** summary cards with Edit links back to each step; "Submit" primary button.

- Bottom: full-width primary button (`brandFill`, 50pt tall, label "Continue" / "Submit"), pinned with `safeAreaInset(edge: .bottom)`, rides above the keyboard. Back is the nav bar back button.
- Draft autosaved; reopening offers "Continue your draft".
- Success: checkmark with `delight` spring + `.success` haptic, copy "Thanks! The community will review it soon.", "Done".
- Error: friendly inline message with "Try again", draft kept.

### 6.8 Onboarding

Three steps over a live map of the user's rough region (or a curated city before permission), blurred 20pt behind a bottom card. Fredoka titles, system body.

1. **Welcome:** "Find places that accept bitcoin" + one line. Primary: "Get started".
2. **Location:** why it helps, "Allow location" primary, "Not now" text button. After allowing, the map unblurs and flies to the user (the reward is the real product, not an animation).
3. **Alerts (optional):** "Hear about new places near you", city suggested from location, "Turn on alerts" / "Skip".

Done: the card slides away (`move`), the sheet rises to `card`. On wide layouts, the onboarding card is a centered 480pt panel over the map, same steps. Feature hints overlay: keep at most 2 hints (search, long-press to add), shown once each, anchored with origin-aware popovers.

### 6.9 Settings

One `NavigationStack` list (sheet on compact `.large`, popover/form sheet on wide):

- **Map:** Map style (Standard / Satellite), Distance units (Auto / Miles / Kilometers).
- **Appearance:** System / Light / Dark.
- **Merchant Alerts:** row with current status ("Nashville · On").
- **Contribute:** Add a business, Report an issue.
- **About:** what BitLocal is, data from BTC Map & OpenStreetMap (attribution), What's New, Privacy Policy, Rate BitLocal, version + build (long-press copies).

Done button trailing. Every row is a native control; no custom chrome.

### 6.10 System screens

- **Deep link unavailable:** sheet with `mappin.slash`, "This place isn't on BitLocal anymore", "Search nearby" action. Plain copy, no monospaced URL dump (keep it in a "Details" disclosure for support).
- **What's New:** sheet with 3 highlights max, each with a symbol; "Continue".
- **Errors:** friendly inline messages; never alerts for recoverable network issues.

---

## 7. Accessibility

- **VoiceOver:** each pin is an accessibility element: "Prickly Pear Coffee Co., coffee shop, 0.3 miles, accepts Lightning, open". Clusters: "12 places, double-tap to zoom". Add a custom rotor "Places" on the map. The list is the accessible equivalent of the map and is always one swipe away.
- Card paging has accessibility actions "Next place" / "Previous place" (the swipe alone is not discoverable).
- Sheet: detents reachable with VoiceOver via the grabber's adjustable action (system), plus an explicit "Expand details" button in the card.
- **Dynamic Type:** everything uses text styles. At AX sizes: list rows stack distance under the name, action row becomes 2×2 grid with labels, card detent grows (clamp raised to 60% height), chips wrap.
- **Contrast:** orange text uses `brandInk` (≥ 4.5:1). Increase Contrast swaps glass/material to solid and thickens pin strokes to 2pt.
- **Color independence:** open/closed always worded; boosted has a "Featured" text tag, not only a gold ring; payment chips are labeled in detail.
- **Reduce Motion / Reduce Transparency:** section 5 and 3.3.
- **Hit targets:** ≥ 44pt; map controls 44×44 minimum.
- **Keyboard and pointer:** full keyboard navigation on iPad (4.6); focus rings visible.
- **Localization:** no text baked into images; layouts tested with German (long) and RTL (Arabic); distance/hour formatting via `Measurement`/`Date.FormatStyle`, not `String(format: "%.1f mi")`.

---

## 8. Adaptive layout checklist (devices × states)

| Context | Width class | Must verify |
| --- | --- | --- |
| iPhone SE / mini portrait | compact | Card detent fits header + actions; no truncation of action labels at default size |
| iPhone Pro Max portrait | compact | Same |
| iPhone landscape | regular (short-height rule) | Sidebar 320pt, map usable, no sheet |
| iPad 11" portrait | regular | Detail pushes in sidebar |
| iPad 11"/13" landscape | expanded | Inspector + sidebar + map ≥ 360pt wide |
| iPad Split View 1/3, Slide Over | compact | Sheet behaves like iPhone |
| iPad Split View 1/2 | regular | |
| Stage Manager live resize | all | Selection re-homes (`updateGeometry(_:)`) without losing scroll or selection; no flicker of a sheet during resize (debounce class changes by 100ms) |
| iPhone Duo folded (outer display, wide and short) | compact | Card row at `card` detent, controls clear of the camera strip (`duo.md` D1–D4) |
| iPhone Duo unfolded sideways | foldColumns | Browse column snapped to the fold, map on the other panel (`duo.md` D5, D10) |
| iPhone Duo unfolded upright | foldStack | Map above the fold, panel below (`duo.md` D8) |
| iPhone Duo partly folded | foldColumns / foldStack | Nothing across the fold (`duo.md` D9) |
| Fold / unfold mid-session | compact ↔ fold layouts | Selection, path, search and zoom survive with no jump (`duo.md` D5–D7, full matrix D1–D21) |
| Dark mode, Increase Contrast, AX5 text, Reduce Motion | all | Screenshots per screen |

Automated: snapshot tests per width class (375, 430, 700, 834, 1194, Duo sizes) for map home, selected merchant, search results, detail, settings. Unit tests for `AppNavigation.updateGeometry(_:)`, `resolvePosture`, deep link routing, and thresholds. iPhone Duo cases D1–D21 are in `duo.md` 8.

---

## 9. Mapping to the architecture plan

| Architecture piece | UI dependency |
| --- | --- |
| v4-only `Merchant` | Card and rows read typed fields (category, payment methods, opening hours, boosted-until, verified-at). Remove placeholder-name heuristics from views; the store guarantees a display name or a category fallback ("Coffee shop") |
| SQLite + R-tree | `MapModel` viewport query on camera idle; list "near map center" uses the same query sorted by distance |
| FTS5 | `SearchModel` sections (places / categories / areas), recents |
| Clustering | Replaces the 25-mile cap; cluster count bubbles; "N places here" card for co-located members |
| Single navigation model | Section 4.2; replaces `viewModel.path`, `selectedElement`, `presentedCommunityArea`, sheet height reporting, and per-layout `@State` detents |
| Small `@Observable` feature models | Replace `ContentViewModel` / `ObservableObject` + `@EnvironmentObject`; views take models via `@Environment(Type.self)` |
| Swift 6 | All UI models `@MainActor`; store actor; `Sendable` merchant snapshots crossing into views |
| Events | Out of scope; no UI slot reserved |

Views that go away or merge: `IPhoneLayoutView` + `IPadLayoutView` → `AdaptiveRootView`; `IPhoneHeaderView`, `InfoButtonView`, `CustomiPadNavigationStackTitleView` → removed; `AboutView` → Settings section; `MapPreviewView` in detail → removed; `MapButtonsView` → `MapControls` (2 buttons); `BottomSheetContentView` → thin `SheetContainer` hosting the shared `BrowseView` / `MerchantDetailView`; `SheetEdgeHeightReader` and sheet-motion plumbing → removed.

---

## 10. Suggested build order

Each step ships on its own and leaves the app working.

1. **Foundations:** `BrandColor`, type rules, `Motion`, `LayoutMetrics`; replace the two oranges; demote orange labels in detail. (Low risk, visible polish.)
2. **Navigation model + AdaptiveRootView** with the three width classes, using today's list/detail views inside. Delete the header bar and sheet-height tracking.
3. **Pins + clustering + viewport queries** (needs the SQLite/R-tree store).
4. **Merchant card + detail reorder**, action row, hours summary, card paging.
5. **Search** on FTS5 with sections and recents.
6. **Communities** mode control + boundaries.
7. **Add Business** flow refresh, long-press to add.
8. **Onboarding (3 steps) + Settings merge + Alerts polish.**
9. **Accessibility pass + snapshot matrix** (section 8), then a fresh-eyes motion review the next day at 0.25× speed (Simulator slow animations) per Emil's "review it tomorrow" rule.

---

## 11. Visible decisions (approved by Joe, 2026-11-08)

All six were approved as recommended ("go with your recommendations"). They are part of the spec, not options.

1. **The top header bar is removed.** The wordmark moves into the sheet/sidebar header; the map gets the space. (Sections 1, 4.6, 6.1.)
2. **Primary buttons use the deeper `brandFill` orange in light mode** (#C25400, white label); pins stay bright orange. (Section 3.2.)
3. **Swiping sideways on the merchant card pages to the next/previous nearby place.** (Sections 4.5, 5, 7.)
4. **Onboarding is 3 steps** (Welcome, Location, Alerts), down from 5. (Section 6.8.)
5. **The embedded map preview is removed from merchant detail**; the compact `full` detent gets a "Show on map" button instead. (Section 6.3.)
6. **Map controls are pinned top-trailing on compact widths** and fade (opacity only) past the `card` detent instead of riding on the sheet. (Sections 1, 4.3.)

Everything else in this document is a technical or craft decision. Nothing in this spec is waiting on product sign-off.
