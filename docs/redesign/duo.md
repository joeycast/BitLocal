# BitLocal on iPhone Duo

Status: design spec, part of the approved redesign (2026-11-08). Design and docs only; nothing built.
Companions: [`ui-redesign.md`](ui-redesign.md) (sections 4–5, 8) and [`architecture-redesign.md`](architecture-redesign.md) (sections 6–7). Where this file is more specific, it wins for iPhone Duo.
Written with `/swiftui-pro` (resizability, design, accessibility and navigation references) and `/emil-design-eng`. Builds on PR #51 ("Pick layout shell by size class for iOS 27 and iPhone Duo") and its screenshots in `~/Developer/BitLocal-pr51-screens/`.

---

## 0. What iPhone Duo changes for BitLocal

iPhone Duo is a folding iPhone with two displays:

- **Outer display (folded):** compact width, regular height in portrait, but **wider and much shorter** than other iPhones (PR #51 captured it at about 466 × 678 pt). The outer camera and the status items sit in a strip at the top-trailing corner (visible in `glass-panel/folded.png` and `duo-fold-layout/duo-folded-fixed.png`, where the old header bar collided with it).
- **Inner display (unfolded):** regular width and regular height, close to 4:3. It has a fold that the system reports as a **division** reserved region. The inner FaceTime camera is an **occlusion** region only while it's in use. System status and bars can move into a **vertical bar** on a hardware-aligned edge (`cards-v2/landscape.png`, `strip-experiment/landscape-strip.png`).
- **Folding doesn't relaunch the app or change `scenePhase`.** It resizes the same scene. Everything the person was doing has to carry across the fold.

Toolchain facts that shape the plan (from `/swiftui-pro`):
- Built with Xcode 26, the app runs on Duo in a phone-shaped compatibility area. Xcode 27.0 widens inner-display use. **Xcode 27.1 enables the full display and vertical bars. The redesign targets Xcode 27.1+.**
- The deployment target stays at iOS 18. Every iOS 27.x API below sits behind `if #available(iOS 27.1, *)` and has a fallback (section 7).

What PR #51 learned, and what this spec keeps:

| PR #51 finding | Carried into this spec |
| --- | --- |
| Device idiom says nothing on iOS 27: the unfolded Duo is a phone-idiom app in a regular-width window, and the old phone shell got stretched to about 4:3 | Choose the layout from size classes, refined by width and fold geometry. Never use `userInterfaceIdiom`, `UIScreen.main` or orientation |
| Sheet detents don't apply in regular width (the sheet turns into a centered form sheet) | The bottom sheet is used only when width is compact. Regular width uses columns or the fold-stacked panel |
| Stale phone-header and sheet insets padded the split map after a fold | Map insets come from one source, `MapModel.obscuredInsets`, recomputed from layout state on every change. No layout keeps its own padding |
| On iOS 27 the sidebar toolbar already sits in the top safe area, so the iOS 26 top compensation pushed search under the buttons | No hand-tuned top offsets. Content stays in the safe area and system toolbars are used |
| Map fitting and centering had to be inset by the floating sidebar so results land beside it | Centering always targets the **unobscured map rect** (section 5) |
| The outer camera strip overlapped the custom header and the map buttons | The header is gone (approved decision 1). Map controls respect the safe area, which already accounts for the outer camera |
| Folded two-across cards (`glass-panel/folded.png`) were clipped at the top edge and too narrow for names | Folded card row: one card plus a peek of the next, with nothing clipped (section 4) |

---

## 1. Postures and layouts

Every posture shows the **same features and the same hierarchy**. Only the container changes (`/swiftui-pro` design rule: folding must never make a feature disappear).

| Posture | How it's detected | Layout | Where the merchant detail goes |
| --- | --- | --- | --- |
| **Folded** (outer display, portrait) | `horizontalSizeClass == .compact` | Compact: full-bleed map plus a system bottom sheet. On short heights the `card` detent shows the **horizontal card row** (section 4) | Sheet: card row at `card`, full detail at `full` |
| **Folded, landscape** | Compact width or `verticalSizeClass == .compact` | Short-height rule from ui-redesign 4.1: a narrow sidebar (min 320 pt) beside the map instead of a sheet | Pushed in the sidebar |
| **Unfolded sideways** (the fold runs vertically through the window) | `horizontalSizeClass == .regular` and an active or inactive `.division` region whose frame is taller than wide | **Fold columns:** browse column on the leading panel, sized to the fold. Map on the trailing panel | Pushed in the browse column. The map stays on its own panel |
| **Unfolded upright** (the fold runs horizontally) | `horizontalSizeClass == .regular` and a `.division` region wider than tall | **Fold stack:** map in the upper region, browse panel in the lower region, with the panel's top edge on the fold | Pushed in the lower panel. The selected pin sits centered in the upper region |
| **Unfolded, partly folded (tabletop/book)** | The same as above, but `isActive == true` | Same layouts. Displacement becomes mandatory: nothing interactive or readable crosses the fold | Same |
| **Unfolded, no fold info** (iOS < 27.1 or no region reported) | `horizontalSizeClass == .regular` | Standard regular layout: sidebar (ideal 360 pt, no max) plus the map. Expanded with inspector only at ≥ 1000 pt width | Sidebar push, or the inspector when expanded |
| **Split View / multiple windows on the inner display** | Whatever size classes the window gets | Same rules per window. A compact-width window behaves like folded | Per window |

Notes:
- PR #51 captured the inner display at about 951 × 669 pt sideways and 669 × 951 pt upright. Neither is wide enough for sidebar + map + inspector (the expanded class needs ≥ 1000 pt), so **on Duo the merchant detail always pushes inside the browse column or panel**. The inspector is an iPad-scale feature. This also avoids a 3-column layout fighting the fold.
- "Upright" and "sideways" are named after the fold's direction **in the window**, not the device orientation. Read it from the division frame and never infer it from rotation. If a device reports a vertical fold in portrait, the fold-columns layout applies.
- Following the Duo heuristics in `/swiftui-pro`: in a tabletop-like pose, the upper region suits content viewed from a distance (the map) and the lower region suits touch (the list, cards, search). That's why fold-stack puts the map on top.

---

## 2. The fold as a layout boundary

Rules, in priority order:

1. **Nothing interactive or readable spans an active fold.** No buttons, text, cards, search field or pins' labels may sit across it. Map tiles may cross it (they're decoration, and reading a map across a hinge works fine).
2. **Column edges align to the fold:**
   - Fold columns: the browse column's trailing edge sits on the division's leading edge. The map starts at its trailing edge.
   - Fold stack: the panel's top edge sits on the division's bottom edge.
   - When the fold is inactive (flat) but `options: .includeInactive` returns a non-zero frame, still snap the column edge to it, so the layout doesn't jump when the person bends the device.
3. **`NavigationSplitView` sidebar width: `navigationSplitViewColumnWidth(min: 320, ideal: 360)` with no `max`.** In a fold-aligned pose the system can widen the sidebar to the fold, and a max would cap it short. This corrects ui-redesign 4.6 and today's `max: 430`.
4. **Map controls (locate, map style) stay inside one region.**
   - In fold columns they sit top-trailing on the map panel, inside its safe area.
   - In fold stack they sit at the trailing edge of the upper region, bottom-aligned above the fold with 12 pt clearance.
   - They never straddle the fold, and they move as one group (the "move the smallest coherent group" displacement heuristic).
5. **Gutter.** The division region's own frame is the gutter. Leave it empty: map tiles show through, and there's no background panel or separator line on the fold itself.
6. **Camera occlusion.** Controls and text stay out of `.occlusion` regions (touches are suppressed there).
   - Outer display: the outer camera always reserves space, and the safe area already covers it, so foreground controls never use `ignoresSafeArea`. Only the map does (it's decoration).
   - Inner display: the FaceTime camera occludes only while active. Re-read the region when `isActive` changes.
7. **Vertical bar.** System toolbars may become a vertical bar on Duo. The map column's toolbar items (locate, map style) are declared as **system `ToolbarItem`s on the map/detail column** in regular width, so on iOS 27.1 they join the vertical bar automatically.
   - Each button gets text plus an SF Symbol: `Button("Locate", systemImage: "location", action: locate)`.
   - Use semantic placements: `.primaryAction` for locate, and `.topBarTrailing` only when no semantic role fits.
   - Floating glass controls are used only in the compact layout. There they read `@Environment(\.toolbarVerticalEdge)` (iOS 27.1+) to sit on the opposite edge from the bar, never a fixed `trailing`.
   - Sidebar toolbar items (settings, wordmark) stay above the sidebar, as the system intends.
8. **Settings sheet.** It only has a Done action, so `toolbarVerticalBehavior(.disabled)` is allowed there (iOS 27.1+). Everywhere else keeps the default vertical adaptation.

---

## 3. Fold and unfold transitions: nothing jumps

Requirement: **selection, sheet/inspector state, search and the map camera all survive the fold, and the selected pin doesn't move relative to its map region.**

### 3.1 State lives above the layout branch

`/swiftui-pro`: when size classes pick different view hierarchies, keep selections and navigation paths above the branch, because state inside a replaced hierarchy resets. Applied here:

| State | Owner (never view `@State` inside a layout branch) |
| --- | --- |
| Selected merchant/community (by ID) | `AppNavigation.selection` |
| Browse path (list → detail → all reviews) | `AppNavigation.path: [Route]`, one array rendered by whichever container is active (sheet stack, sidebar stack, lower panel stack) |
| Compact sheet detent | `AppNavigation.sheetDetent`, plus `lastCompactDetent` restored when folding back |
| Search query, scope, focus | `SearchModel.query` and `AppNavigation.isSearching` (drives `searchable(isPresented:)`) |
| Map camera | `MapModel.camera` (center, distance, heading, pitch) and `MapModel.focus` (the coordinate that should stay visually fixed) |
| Detail scroll position | `MerchantDetailModel.scrollAnchor`, keyed by merchant ID |
| Card-row position (folded) | Bound to `AppNavigation.selection` through `scrollPosition(id:)` |

`NavigationSplitView` can reset its own selection to `nil` when it expands. BitLocal doesn't give it ownership: `AppNavigation` re-fills the column contents from `selection` and `path` on every layout change.

### 3.2 How each piece carries across

| Transition | Selection | Panel state | Map camera |
| --- | --- | --- | --- |
| **Fold** (inner → outer) | Kept | If a merchant is selected: the sheet appears at `card` with that merchant's card first in the card row. If not: the sheet returns to `lastCompactDetent`. A path deeper than detail (e.g. all reviews) appears at `full` | Same **zoom level** (meters per point) and focus; recentered in the new unobscured rect |
| **Unfold** (outer → inner) | Kept | `path` is shown in the browse column (fold columns) or lower panel (fold stack). The sheet is dismissed **without animation**: `withTransaction(\.disablesAnimations, true)` around the layout switch so it doesn't slide away while the columns appear | Same zoom and focus, recentered in the map region |
| **Fold stack ↔ fold columns** (rotate while unfolded) | Kept | Same path, other container | Same zoom and focus |
| **Search active during fold** | Kept | Query and results kept. Focus is restored by setting `isSearching = true` after the layout settles (one runloop), so the keyboard returns where the field now lives | Unchanged |

**Why keep the zoom level and not the visible region:** if the visible region were preserved, folding to the narrower outer display would zoom the map out. Neighbors would then re-cluster around the selected pin, and its "standing alone" state from section 5 would collapse. Keeping meters per point keeps pins the same size, clusters the same, and the selected pin alone.

**Camera recenter math** (one pure function, unit-tested):

```swift
/// Keeps `focus` at the center of the unobscured rect after a layout change,
/// at the same meters-per-point zoom. No animation: the layout change is the motion.
func camera(afterLayoutChange old: MapCamera, focus: CLLocationCoordinate2D,
            oldMapSize: CGSize, newMapSize: CGSize, newUnobscured: CGRect) -> MapCamera
```

Apply the new camera in the same transaction as the layout switch, with animations disabled. A camera fly during a fold reads as the app moving the world under the person's hands.

### 3.3 One map instance

The map is the largest and most expensive view, and recreating it flashes tiles and resets gestures. Primary approach:

- `AdaptiveRootView` is a `ZStack` with the **map as a persistent bottom layer**, outside the layout branch. The layout containers (sheet, `NavigationSplitView`, fold stack) sit above it.
- Where the map should show, those containers are transparent: the detail column uses `.containerBackground(.clear, for: .navigation)` and non-interactive clear content.
- The map gets `obscuredInsets` through `.safeAreaPadding(...)`, so MapKit for SwiftUI frames the camera inside the uncovered area.

This is the riskiest assumption in the Duo plan, so it's the first spike in phase 3 of the migration (architecture-redesign section 13). Check on iOS 18, 26 and 27.1 that:
- map gestures pass through the transparent detail column;
- the floating iOS 26+ sidebar shows the map beneath it, matching PR #51's finding that results must land beside the sidebar;
- VoiceOver order stays sane.

**Fallback** if the spike fails on some OS: each layout hosts its own `Map`, rebuilt from `MapModel.camera` inside the same no-animation transaction, with a 120 ms opacity crossfade to hide the tile reload. Selection, path and camera still survive, because they never lived in the view.

### 3.4 Motion during folding

Applying the `/emil-design-eng` frequency rule: folding happens several times a day and is physical. The hardware is the animation.
- No custom transition on fold or unfold, no camera fly, no sheet slide.
- Panel contents keep identity (same `id`s), so SwiftUI doesn't fade them in and out.
- `onHingeChange` is **not** used for layout. Its only optional use: while the hinge is partly open in the fold-stack posture, the lower panel's grabber hides because the panel can't collapse during tabletop use. It resets when `context.hinge` is `nil` or the status ends. This is optional polish behind `#available(iOS 27.1, *)`.

---

## 4. Folded merchant card row

On the outer display, the regular `card` detent (260–380 pt) would cover more than half of a ~678 pt-tall screen. So in compact width with **height < 740 pt** (outer display, plus iPhone SE/mini class), the `card` detent shows a **horizontal card row** instead of the vertical list and single card:

```
┌───────────────────────────────────────────────┐
│  [ search field ]                 [Places|Comm]│
│ ┌──────────────────────────────────┐ ┌───────  │
│ │ ₿  Prickly Pear Coffee Co.  0.3mi│ │ ₿  Nig  │  ← one card + peek of next
│ │    Coffee · Open · Closes 6 PM   │ │    Bar  │
│ │    ⚡ Lightning      [Directions]│ │    ⚡   │
│ └──────────────────────────────────┘ └───────  │
└───────────────────────────────────────────────┘
```

- **Content:** the selected merchant first (if any), then nearby merchants in `BrowseModel` order: the same list the vertical list shows, so nothing is folded-only.
- **Card size:** `containerRelativeFrame(.horizontal) { width, _ in width * 0.84 }`, so one card is fully readable and the next peeks about 16% as a swipe cue. This replaces PR #51's two-across cards, whose names truncated at ~233 pt. The height comes from the card's content (no fixed frame), and the sheet's `card` detent is `.height` measured from the row (about 170–190 pt at default text size).
- **Swipeable:** `ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetLayout()` + `.scrollTargetBehavior(.viewAligned)` + `.scrollIndicators(.hidden)`. This is the folded form of approved decision 3 (swipe to the next place). It uses system paging physics, so a flick works with no custom gesture code.
- **No clipped top edges.** The fix for `glass-panel/folded.png`:
  - `.scrollClipDisabled()` on the row, so card shadows and the selected card's lift aren't cut off at the scroll view's bounds.
  - The vertical padding lives **inside** the scroll content (`.contentMargins(.vertical, 8, for: .scrollContent)`), not as a fixed frame smaller than the cards.
  - Horizontal insets come from `.contentMargins(.horizontal, 16, for: .scrollContent)`, so the first card lines up with the search field and the last card can scroll to the leading edge.
  - Card shape: `ConcentricRectangle()` (iOS 26+; `.rect(cornerRadius: 16)` before), so the corners follow the sheet and the outer display's uneven corners.
- **Selection sync, both ways:** `.scrollPosition(id: $cardRowID)`, where `cardRowID` mirrors `AppNavigation.selection`.
  - Swiping settles on a card, selects it (`.selection` haptic via `sensoryFeedback`) and pans the map only if the pin is outside the unobscured rect.
  - Tapping a pin scrolls the row to that card. `withAnimation(Motion.select)` is used only when the change came from the map. Swipe-driven changes don't re-animate.
- **Each card is a `Button`.** The tap behavior is in section 5. The Directions button inside the card is its own `Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")` with a 44 pt hit area.
- **Accessibility:**
  - The row is a list for VoiceOver: each card reads "name, category, distance, open status, payments", with "Next place"/"Previous place" accessibility actions.
  - At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`), the row falls back to the vertical list at the `full` detent through `ViewThatFits`, because a horizontal row of huge text helps nobody.
  - Reduce Motion: the row scrolls without the spring.
- **Dragging up** to `full` swaps the row for the full detail of the selected card (or the vertical list if nothing is selected). Dragging back down returns to the row at the same position.

---

## 5. Tap-a-card behavior: reveal the pin

Applies to tapping a card in the folded row, a list row, a search result, a deep link, or a merchant-alert notification. It's one function: `MapModel.reveal(_ id: MerchantID)`.

1. **Select first.** `AppNavigation.select(id, source:)`. The pin switches to its selected style **immediately** (`Motion.select` spring, 28 → 36 pt, label shown), even if it's currently inside a cluster:
   - `MerchantClusterer` always excludes the selected ID from clustering (architecture-redesign section 6).
   - The cluster it came from recounts (e.g. "5" becomes "4").
   - The selected pin renders above clusters with a higher `zIndex`.
2. **Zoom until the pin stands alone.**
   - Ask the store for the nearest neighbor of the selected merchant within the current filter (an R-tree box query, then distance), giving distance `d` in meters.
   - A pin stands alone when its neighbor is at least one clustering cell away on screen: `metersPerPoint ≤ d / (cellSize + pinDiameter)`, with cellSize 60 pt and pinDiameter 36 pt.
   - Target zoom = the larger of that and street level, clamped to the map's maximum zoom.
   - **Never zoom out** to satisfy this: if the map is already closer, keep the zoom.
   - If `d` is about 0 (several places in one building), stop at max zoom. The selected pin still stands alone (rule 1), and the rest show as a "+3 here" cluster that opens the co-located list.
3. **Center it above the panel.** The target center puts the pin at the **center of the unobscured map rect**, which depends on the layout:

   | Layout | Unobscured map rect |
   | --- | --- |
   | Folded (sheet) | Area above the sheet's `card` detent, below the top safe area |
   | Folded landscape | Area beside the sidebar |
   | Fold columns | The trailing panel (beside the fold) |
   | Fold stack | The upper region (above the fold) |
   | Regular / expanded (non-Duo) | Beside the sidebar and the inspector |

   It's computed from `MapModel.obscuredInsets` plus the division frame. Never from `UIScreen`, and never from guessed padding.
4. **One camera move.** A single `MapCamera` change (center and distance together) with MapKit's camera animation. There's no zoom-then-pan two-step. With Reduce Motion it jumps.
5. **Skip when it's already right.** If the pin already stands alone and sits inside the middle 60% of the unobscured rect, don't move the camera; just select. This is the ui-redesign 5 rule ("don't move the world on every tap"), extended to zoom.

`reveal` is the only path that moves the camera for a selection, so every entry point behaves the same in every posture.

---

## 6. Other screens on Duo

- **Search:** `searchable` stays in the browse container (sheet, browse column or lower panel). In fold stack, the keyboard covers the lower panel, so the map above stays visible. Results never span the fold.
- **Merchant detail:** an ordinary `List` inside the browse container. Per `/swiftui-pro` it isn't displaced: system lists already adapt, and a horizontal fold through scrolling content needs no special handling.
- **Communities:** same containers. Boundaries are drawn on the map panel, and fitting a boundary uses the unobscured rect.
- **Add Business:** presented as a sheet. On the inner display it uses `.presentationSizing(.form)` (the system sheet adjusts around the fold). The location step's map + center pin lives inside the sheet. On the outer display the steps scroll and the primary button is pinned with `safeAreaBar` (iOS 26+; `safeAreaInset` before), so it stays reachable on the short display.
- **Onboarding:** the bottom card scrolls (or uses `ViewThatFits`) so its buttons never fall off the short outer display. On the inner display it's a centered 480 pt panel placed within one fold region, never across the fold.
- **Settings / Alerts:** system `NavigationStack` lists in a sheet. No Duo-specific code.
- **Multiple windows:** with two windows open, closing the device keeps the most recent one active and backgrounds the other. `AppNavigation` is per scene and restores itself through `@SceneStorage`, so both windows keep their state.

---

## 7. Detection: exact APIs and fallbacks

### 7.1 Inputs

| Input | API | Availability | Used for |
| --- | --- | --- | --- |
| Size classes | `@Environment(\.horizontalSizeClass)`, `@Environment(\.verticalSizeClass)` | All | Primary layout choice. Check `== .regular` for expanded layouts, never `!= .compact` (size classes are optional) |
| Container size | `onGeometryChange(for: CGSize.self) { $0.size } action: { ... }` on the root | iOS 18 (back-deployed) | Regular vs expanded (1000 pt), the short-height rules (500 pt sidebar rule, 740 pt card-row rule) |
| Fold | `GeometryProxy.reservedRegions(kind: .division, options: .includeInactive)`, each `ReservedRegion` with `frame`, `margins`, `isActive` | iOS 27.1+, Xcode 27.1 | Fold columns vs fold stack, column snapping, displacement |
| Cameras | `GeometryProxy.reservedRegions(kind: .occlusion)` | iOS 27.1+ | Keeping floating controls clear of the active inner camera |
| Vertical bar side | `@Environment(\.toolbarVerticalEdge)` (optional; `nil` when no vertical bar applies) | iOS 27.1+ | Placing compact floating controls opposite the bar |
| Hinge | `onHingeChange { _, context in ... }`, `context.hinge?.status`, `.angle` | iOS 27.1+ | Optional effects only (section 3.4). **Never layout** |
| Text size | `@Environment(\.dynamicTypeSize)` (`.isAccessibilitySize`) | All | Card row fallback to vertical list |

Not used: `UIDevice.current.userInterfaceIdiom`, `UIScreen.main` (deprecated in iOS 26 and wrong on a two-display device), orientation, forced size-class overrides, `ArrangementView`.

`ArrangementView` is left out on purpose: its children must not contain `NavigationStack`, and BitLocal's browse panel is a navigation stack. The fold-stack and fold-columns layouts are a small custom `Layout` instead.

### 7.2 Resolution

```swift
enum LayoutPosture: Equatable, Sendable {
    case compact(shortHeight: Bool)                    // sheet; card row when shortHeight
    case compactLandscape                              // narrow sidebar + map
    case regular                                       // sidebar + map (no fold info)
    case expanded                                      // sidebar + map + inspector (≥ 1000 pt)
    case foldColumns(divisionFrame: CGRect, isActive: Bool)
    case foldStack(divisionFrame: CGRect, isActive: Bool)
}

// Pure and unit-tested. Inputs are plain values so tests never need a device.
func resolvePosture(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?,
                    size: CGSize, divisions: [CGRect: Bool]) -> LayoutPosture
```

Order: compact width → `.compact` / `.compactLandscape`. Then regular width with a division → fold layouts (vertical division = columns, horizontal = stack). Then width ≥ 1000 → `.expanded`. Otherwise `.regular`.

Geometry reading follows `/swiftui-pro`:
- Use `onGeometryChange` on the laid-out root so region frames share its coordinate space.
- The transform closure is `@Sendable` (`nonisolated` under default MainActor isolation) and returns an `Equatable & Sendable` snapshot. That way updates fire only when the posture actually changes, not every frame of a resize.

```swift
// Inside AdaptiveRootView; the iOS 27.1 branch adds fold data, the fallback passes [:].
.onGeometryChange(for: GeometrySnapshot.self) { proxy in
    if #available(iOS 27.1, *) {
        GeometrySnapshot(size: proxy.size,
                         divisions: proxy.reservedRegions(kind: .division, options: .includeInactive)
                            .filter { !$0.frame.isEmpty }
                            .map { .init(frame: $0.frame, isActive: $0.isActive) },
                         occlusions: proxy.reservedRegions(kind: .occlusion)
                            .filter(\.isActive).map(\.frame))
    } else {
        GeometrySnapshot(size: proxy.size, divisions: [], occlusions: [])
    }
} action: { navigation.updateGeometry($0) }
```

(The exact `reservedRegions` signature, `kind:options:layoutDirectionBehavior:`, comes from the iOS 27.1 SDK. Recheck it against the shipping SDK when implementing. Frames already account for right-to-left mirroring.)

### 7.3 Fallbacks

| Missing | Behavior |
| --- | --- |
| iOS < 27.1 at runtime | No fold or occlusion data: regular width uses `.regular`/`.expanded` (sidebar + map, sidebar ideal 360 pt, no max). Content may cross the fold on a flat inner display, which is acceptable because it's flat. No vertical-bar placement; system toolbars still behave |
| Built with Xcode < 27.1 | The app runs in Duo's compatibility area as a phone. The compact layout and card-row rules still give a good result. **Release builds use Xcode 27.1+** (CI already selects Xcode 26.3, which has to move to 27.1: an architecture phase 1 task) |
| Division reported but zero frame (inactive) | No snapping. The normal regular layout is used until the region becomes non-zero |
| Unexpected fold direction or multiple divisions | Use the largest division. If its direction is ambiguous (near-square frame), fall back to `.regular` |
| Map-layer spike fails (3.3) | Per-layout `Map` rebuilt from `MapModel.camera` with a 120 ms crossfade |

---

## 8. Test plan (iPhone Duo simulator, Xcode 27.1)

Posing: `simctl` can't fold or rotate the Duo simulator. Use the RocketSim CLI if it's installed (`rocketsim duo pose closed|book|open`, `rocketsim duo hinge` to read the state). Otherwise use Xcode's Device Hub manually. Any case not run is listed as untested in the PR, never assumed.

### 8.1 Automated (unit, no simulator)

- `resolvePosture`: a table test over size classes × sizes (466×678, 678×466, 669×951, 951×669, iPhone 375×812, iPad 820×1180 / 1180×820) × division (none, vertical, horizontal, inactive zero-frame, active).
- Camera recenter: the focus stays at the unobscured center across every posture pair. Meters per point are unchanged.
- `reveal`: the nearest-neighbor zoom formula, the "never zoom out" rule, co-located merchants, the skip-when-visible rule, and the selected ID never clustered.
- `AppNavigation` fold round-trips: path, selection, detent, search state and `lastCompactDetent` restored for each transition in section 3.2.

### 8.2 Simulator cases (snapshot + manual)

| # | Setup | Action | Expected |
| --- | --- | --- | --- |
| D1 | Folded, portrait, default text | Launch | No header. Controls clear of the camera strip. Sheet at `peek`; drag to `card` shows the card row |
| D2 | Folded | Swipe the card row both ways | One card plus a peek. Pages snap. The map pin selection follows. **No clipped card tops or shadows** |
| D3 | Folded, merchant in a "5" cluster | Tap its card | Pin leaves the cluster at once in the selected style. The cluster shows "4". One camera move to the standing-alone zoom, centered above the sheet |
| D4 | Folded, two merchants in the same building | Tap one | Max zoom, the selected pin alone, "+1 here" badge |
| D5 | Folded, merchant selected, sheet at `card` | Unfold flat (sideways) | Detail in the leading column, sidebar edge on the fold. The pin is in the same spot relative to the map panel center, at the same zoom. No sheet slide, no camera fly |
| D6 | Unfolded sideways, detail open, scrolled halfway | Fold | Sheet at `card` with the same merchant first. Dragging to `full` shows the detail at the same scroll position |
| D7 | Unfolded, search active with "cof" typed | Fold, then unfold | Query and results kept each time. The keyboard returns in the field's new home |
| D8 | Unfolded upright (horizontal fold) | Launch / select a merchant | Map above the fold, panel below with its top edge on the fold. The pin is centered in the upper region. Controls in the upper region above the fold |
| D9 | Unfolded, book pose (partly folded, active division) | Open detail, communities and search | Nothing readable or tappable across the fold. The gutter is empty |
| D10 | Unfolded | Rotate sideways ↔ upright | Switches between fold columns and fold stack. Selection, path and zoom kept |
| D11 | Unfolded, FaceTime camera active (occlusion) | Look at floating controls | Nothing in the occlusion frame |
| D12 | Unfolded, iOS 27.1 vertical bar present | Check map column toolbar | Locate and map style appear in the vertical bar with labels in overflow. The sidebar's settings stay above the sidebar |
| D13 | Inner display, Split View with another app on either side | Use BitLocal in compact and regular widths | Compact behaves like folded, regular like the "no fold info" layout. No feature missing |
| D14 | Two BitLocal windows on the inner display | Fold | The most recent window stays active with its state. The other restores on return |
| D15 | Folded landscape | Launch, select | Narrow sidebar + map. Detail pushes in the sidebar |
| D16 | Folded, AX5 text | Open the `card` detent | The row falls back to the vertical list, and nothing truncates into uselessness |
| D17 | Arabic (RTL), unfolded sideways | Layout | The browse column on the leading (right) panel snaps to the fold. Controls mirror correctly. Region frames are not mirrored twice |
| D18 | Folded, dark mode + Reduce Motion + Reduce Transparency | D2, D3 | No springs (camera jumps), solid backgrounds instead of glass |
| D19 | Onboarding on folded and unfolded | Run all 3 steps | Buttons reachable on the outer display. The panel never spans the fold |
| D20 | Add Business on folded | Steps 1–5 | The primary button stays visible above the keyboard |
| D21 | Resize extremes (Stage Manager-like inner windows) | Narrowest, widest, shortest, tallest, square | No overlap, no clipped content, no sprawling text |

Maestro: add `duo-fold-roundtrip.yaml` (select, then the pose script, then assert the selected title is still visible) once the pose step can be scripted via RocketSim. Until then, D5–D10 are manual and listed in each PR's test notes.

---

## 9. Changes this spec makes to the companion docs

These have been applied in the companion files:
- ui-redesign 4.1: the layout choice starts from size classes, with width and fold refining it, and Duo rows point here.
- ui-redesign 4.6: sidebar width is min 320, ideal 360, **no max**.
- ui-redesign 8: the Duo checklist rows point to section 8 here.
- architecture 6: the map view is **SwiftUI `Map`**, not an `MKMapView` bridge. Because BitLocal clusters in its own code, the annotation count is bounded (a few hundred at most), which is what makes SwiftUI `Map` viable. `MKMapView` stays as a fallback only if performance tests fail.
- architecture 7: `AppNavigation` owns `path` (a single array), `lastCompactDetent`, and the posture resolved from geometry.
