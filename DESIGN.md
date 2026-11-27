---
name: BitLocal
description: Calm, Apple Maps–grade native iOS utility for discovering Bitcoin merchants and communities across iPhone, iPad, and folding iPhone Duo.
colors:
  bitcoin-orange: "#FC780F"
  marker-orange: "#FF6D00"
  semantic-primary-text: "#000000"
  semantic-secondary-text: "#3C3C4399"
  semantic-surface-light: "#FFFFFF"
  semantic-surface-dark: "#1C1C1E"
  semantic-grouped-light: "#F2F2F7"
  semantic-grouped-dark: "#000000"
  semantic-separator: "#3C3C434A"
  status-open: "#34C759"
  status-warning: "#FF9500"
  status-error: "#FF3B30"
typography:
  display:
    fontFamily: "Fredoka-Medium, -apple-system, sans-serif"
    fontSize: "28pt"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "0em"
  title:
    fontFamily: "-apple-system, SF Pro Display, sans-serif"
    fontSize: "22pt"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0em"
  headline:
    fontFamily: "-apple-system, SF Pro Text, sans-serif"
    fontSize: "17pt"
    fontWeight: 600
    lineHeight: 1.29
    letterSpacing: "-0.02em"
  body:
    fontFamily: "-apple-system, SF Pro Text, sans-serif"
    fontSize: "17pt"
    fontWeight: 400
    lineHeight: 1.29
    letterSpacing: "-0.02em"
  subheadline:
    fontFamily: "-apple-system, SF Pro Text, sans-serif"
    fontSize: "15pt"
    fontWeight: 400
    lineHeight: 1.33
    letterSpacing: "-0.01em"
  footnote:
    fontFamily: "-apple-system, SF Pro Text, sans-serif"
    fontSize: "13pt"
    fontWeight: 400
    lineHeight: 1.38
    letterSpacing: "0em"
  caption:
    fontFamily: "-apple-system, SF Pro Text, sans-serif"
    fontSize: "12pt"
    fontWeight: 500
    lineHeight: 1.33
    letterSpacing: "0em"
rounded:
  xs: "3pt"
  sm: "10pt"
  md: "12pt"
  lg: "14pt"
  surface: "16pt"
  sheet: "22pt"
  pill: "9999pt"
spacing:
  xxs: "4pt"
  xs: "6pt"
  sm: "8pt"
  md: "12pt"
  surface-x: "14pt"
  page-x: "16pt"
  section-gap: "18pt"
  bottom-pad: "28pt"
components:
  button-primary:
    backgroundColor: "{colors.bitcoin-orange}"
    textColor: "{colors.semantic-surface-light}"
    typography: "{typography.headline}"
    rounded: "{rounded.lg}"
    height: "44pt"
    padding: "12pt 16pt"
  button-tactile-row:
    backgroundColor: "transparent"
    textColor: "{colors.semantic-primary-text}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.md}"
    height: "44pt"
    padding: "8pt 12pt"
  surface-grouped:
    backgroundColor: "{colors.semantic-surface-light}"
    rounded: "{rounded.surface}"
    padding: "12pt 14pt"
  chip-filter:
    backgroundColor: "{colors.semantic-grouped-light}"
    textColor: "{colors.semantic-primary-text}"
    typography: "{typography.footnote}"
    rounded: "{rounded.pill}"
    height: "36pt"
    padding: "6pt 12pt"
  chip-filter-active:
    backgroundColor: "{colors.bitcoin-orange}"
    textColor: "{colors.semantic-surface-light}"
    typography: "{typography.footnote}"
    rounded: "{rounded.pill}"
    height: "36pt"
    padding: "6pt 12pt"
  input-search:
    backgroundColor: "{colors.semantic-grouped-light}"
    textColor: "{colors.semantic-primary-text}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    height: "44pt"
    padding: "8pt 12pt"
---

# Design System: BitLocal

## Overview

**Creative North Star: "The Local Compass"**

BitLocal is a calm, Apple Maps–grade native iOS utility for finding physical businesses and local communities that accept Bitcoin. The map is the primary workspace; every sheet, search bar, detail card, and toolbar floats gently over it using native iOS translucent materials and Liquid Glass so spatial orientation is never lost.

As an Operate-mode native utility, clarity, scanability, and Apple HIG fluency outrank decorative expression. Brand identity lives in disciplined, unmistakable moments: a single warm Bitcoin orange accent (`#FC780F` in Display-P3) and the friendly `Fredoka-Medium` wordmark in navigation headers, while every interactive control, list, and detail screen feels indistinguishable from a first-party Apple Maps or Settings experience across Light Mode, Dark Mode, Dynamic Type, iPhone, iPad, and folding iPhone Duo.

We explicitly reject "crypto app" tropes (neon gradients, dark-only glow cards, ALL-CAPS eyebrow labels, pill-badge soup, and custom-drawn navigation bars).

**Key Characteristics:**
- Map-first spatial layout with native translucent sheets and sidebars
- Single Display-P3 Bitcoin orange accent reserved strictly for interactive tint, active states, and map pins
- Full native iOS ergonomics: 44×44 pt touch targets, Dynamic Type scaling, SF Symbols, and Reduce Motion parity
- Tactile, interruptible micro-interactions grounded in `BitLocalMotion` and `.sensoryFeedback()`
- Adaptive size-class geometry that transitions seamlessly across iPhone, iPhone Duo (outer + unfolded inner), and iPad

## Colors

BitLocal uses one warm brand accent over Apple's semantic system palette so Light Mode, Dark Mode, and Increased Contrast work automatically without hand-maintained dark hex overrides.

### Primary
- **Warm Bitcoin Orange (`AccentColor`, Display-P3 `#FC780F`)**: Primary app tint for interactive controls, active quick-filter chips, verified/primary action buttons, and the `BitLocal` wordmark.
- **Map Marker Orange (`MarkerColor`, Display-P3 `#FF6D00`)**: High-visibility map pin and cluster fill in `MapView` / `AnnotationView`, calibrated to stay legible against both standard and satellite/hybrid map tiles.

### Neutral
- **Primary Label (`Color.primary` / `.primary`)**: Merchant titles, community names, primary detail values, and active toolbar icons.
- **Secondary & Tertiary Labels (`.secondary`, `.tertiary`)**: Distances, category subtitles, timestamps, trailing chevrons, and muted chrome. Always prefer hierarchical foreground styles over manual `.opacity(...)`.
- **Translucent Surfaces (`BitLocalSheetSurface`, `.ultraThinMaterial`, `.thinMaterial`)**: Inside Liquid Glass / translucent bottom sheets, grouped cards (`PlaceGroupedSurface`), secondary action buttons, pills, filter chips, and search bars use `BitLocalSheetSurface` primary-tinted translucent fills (`Color.primary.opacity(...)`) rather than stacked `.regularMaterial`, keeping clear elevation in Light Mode and calm translucency in Dark Mode while letting the search bar follow the sheet background.
- **Grouped & System Backgrounds (`Color(.systemGroupedBackground)` / native `List(.insetGrouped)` / `.background`)**: Settings, forms, and non-map modal sheets.
- **Hairline Borders (`BitLocalSheetSurface.borderColor` at `0.5pt`)**: Crisp structural definition around `PlaceGroupedSurface` cards, pills, and search capsules (automatically strengthened when `colorSchemeContrast == .increased`) without drop-shadow clutter.

### Status
- **Open / Success (`.green`)**: Live "Open" hours indicator and saved/copied confirmation states. Always paired with text or an SF Symbol (never color alone).
- **Caution / Offline (`.orange`)**: Offline Travel Mode banner and unverified/boosted callouts.
- **Destructive / Error (`.red`)**: Validation errors, failed lookup states, and destructive actions.

### Named Rules
**The One-Accent Rule.** Warm Bitcoin Orange (`#FC780F`) is reserved for interactive affordances, active filters, primary CTAs, and map pins—targeting ≤10% of any viewport. Never wash entire cards or passive chrome in orange.

**The Semantic-Neutral Rule.** Never hardcode hex grays, `#FFFFFF`, or `#000000` in SwiftUI views. Use SwiftUI semantic styles (`.primary`, `.secondary`, `.tertiary`, `.background`, `.regularMaterial`) so Dark Mode and Increased Contrast stay first-class automatically.

## Typography

**Display Font:** `Fredoka-Medium` (`Fonts/CustomFonts.swift`, registered at launch)
**Body & UI Font:** System San Francisco (`SF Pro Display` / `SF Pro Text`) via SwiftUI Dynamic Type styles
**Monospace / Technical Values:** `.monospaced()` modifier on system text styles (for place IDs, Lightning addresses, and raw technical copy)

**Character:** Friendly, approachable geometric warmth in the `BitLocal` header paired with crisp, legible San Francisco throughout the utility interface.

### Hierarchy
- **Display Wordmark** (`Fredoka-Medium`, `26–32pt`, always paired with `relativeTo: .title` / `.title2` / `.largeTitle`): Used exclusively for the `BitLocal` brand wordmark in top-level map headers (`IPhoneLayoutView`, `IPhoneHeaderView`, `CustomiPadNavigationStackTitleView`) and `AboutView`.
- **Place & Screen Titles** (`.title2.bold()` / `.title3.bold()`): Merchant names in `BusinessDetailView`, community names in `CommunityDetailView`, and onboarding headlines.
- **Section & Row Headlines** (`.headline` / `.subheadline.weight(.semibold)`): Grouped section headers, merchant row titles, and primary button labels.
- **Body & Values** (`.body` / `.subheadline`): Descriptions, addresses, hours, contact rows, and search inputs.
- **Metadata & Chips** (`.footnote` / `.caption`): Distances, verification freshness, filter chips, and helper footers.

### Named Rules
**The Dynamic Type Floor Rule.** Never force hardcoded `.font(.system(size: ...))` in SwiftUI views, and never use `.caption2` for readable labels (minimum readable floor is `.caption` / ~11–12pt). Any custom font or icon column width must use `relativeTo:` or `@ScaledMetric`.

**The Sentence-Case Rule.** Use natural sentence case or Title Case for headings, section headers, and buttons—never ALL-CAPS tracked eyebrows or uppercase pill badges.

## Layout

BitLocal adapts continuously to window dimensions using `@Environment(\.horizontalSizeClass)`, `@Environment(\.verticalSizeClass)`, container geometry, and `@Environment(\.isVerticalToolbarActive)` via [`AppLayoutMode`](file:///home/antigravity/joeycast/BitLocal/Shared/Helpers/AppLayoutMode.swift). Layout decisions never branch on `UIDevice.current.userInterfaceIdiom` or `UIScreen.main`.

### Adaptive Shells
- **Compact Bottom Sheet (`AppLayoutMode.compactSheet` — standard iPhone, iPhone Duo outer display, iPhone Duo unfolded portrait, Split View / Slide Over):** Full-bleed map with a persistent collapsible bottom sheet (`BottomSheetDetents`: collapsed peek, medium browse, large detail).
- **Leading-Side Collapsible Sheet (`AppLayoutMode.compactSheet` with `leadingCollapsibleSheetWidth` — iPhone Duo unfolded landscape with vertical toolbar):** Map fills the full canvas while the persistent sheet pins to the leading side (~42% width, clamped to `380–420pt`, staying ≥16pt clear of the center fold in both LTR and RTL), leaving the trailing side clear for the system vertical bar and unobstructed map browsing.
- **Split Sidebar (`AppLayoutMode.splitSidebar` — iPad regular width & regular height without vertical toolbar):** Native `NavigationSplitView` with persistent sidebar list/detail and full-bleed map detail column.

### Spacing Rhythm
- **Page horizontal margin:** `16pt` on detail views, sheets, and search headers.
- **Section vertical rhythm:** `18pt` between major detail sections (`BusinessDetailView`, `CommunityDetailView`).
- **Card internal padding:** `12pt` vertical × `14pt` horizontal (`PlaceGroupedSurface` default; `6pt` vertical for stacked divider rows).
- **Tight element spacing:** `4–8pt` within rows, chips, and icon-text pairs.
- **Bottom scroll breathing room:** `28pt` below final detail content above the safe area.

### Named Rules
**The Feature-Parity Rule.** Folding iPhone Duo or resizing an iPad window must never hide or drop a feature. Selections and `ContentViewModel.path` (`BitLocalNavigationRoute`) live above layout branches so fold/resize transitions preserve state.

**The Safe-Area Respect Rule.** Unqualified `.ignoresSafeArea()` is allowed only on decorative backgrounds, maps, and dimming scrims—never on readable text or interactive controls. Interactive screens that might overflow on iPhone Duo's short outer display must scroll (`ScrollView`) or adapt via `ViewThatFits`.

## Elevation & Depth

BitLocal is a **translucent material-layered** system, not a drop-shadow system. Depth is communicated through native iOS vibrancy, blur, and subtle `0.5pt` hairline borders rather than ambient glow shadows.

### Surface Hierarchy
1. **Canvas (Map):** Full-bleed `MKMapView` with live markers and community polygons.
2. **Primary Chrome (Liquid Glass / Sheets / Sidebars):** Native iOS 26+ Liquid Glass toolbars and translucent sheets; `.thinMaterial` / `.regularMaterial` fallbacks on iOS 18.
3. **Grouped Detail Surfaces (`PlaceGroupedSurface`):** `.regularMaterial` rounded cards (`16pt`) with a `0.5pt` hairline border (`Color(.separator).opacity(0.35)`).
4. **Controls & Pills:** Native `.bordered` / `.borderedProminent` buttons, native Liquid Glass toolbar pills (`MapControlToolbarContent`), and crisp capsule filter chips.

### Motion & Tactile Feedback (`BitLocalMotion`)
Motion is crisp, interruptible, and functional—never decorative:
- **Entrances (`BitLocalMotion.strongEaseOut`):** `cubic-bezier(0.23, 1, 0.32, 1)`, `220ms` — banners, search state reveals, filter updates.
- **Tactile Press (`BitLocalMotion.press`):** `cubic-bezier(0.23, 1, 0.32, 1)`, `140ms` — button (`0.97×`) and row (`0.985×`) press feedback via `.tactilePress` and `.tactileRow`.
- **Exits (`BitLocalMotion.fastExit`):** `cubic-bezier(0.23, 1, 0.32, 1)`, `160ms` — scroll-past navigation title and quick dismissals.
- **Disclosures (`BitLocalMotion.disclosureSpring`):** `spring(duration: 0.28, bounce: 0.0)` — opening hours expansion and inline details.
- **Micro-Morphs (`BitLocalMotion.morphSpring`):** `spring(duration: 0.26, bounce: 0.12)` — copy-to-checkmark transitions (`TactileCopyButton`).
- **Haptics:** Prefer SwiftUI `.sensoryFeedback(.selection / .impact / .success, trigger:)` over imperative UIKit generators.

### Named Rules
**The Material-Over-Shadow Rule.** Do not add decorative drop shadows or colored glow halos to cards, icons, or hero badges. Use `.regularMaterial` + `0.5pt` hairline border for separation.

**The Reduce-Motion Rule.** Every custom animation, scale effect, shimmer, and slide transition must honor `@Environment(\.accessibilityReduceMotion)`, falling back to `BitLocalMotion.reducedFade` (`easeOut`, `160ms`) or static opacity.

## Shapes

BitLocal uses Apple's continuous squircle geometry (`RoundedRectangle` default `.continuous` style) with radii scaled to container prominence:
- **Micro badges / attribution (`3pt`):** Map attribution pill.
- **Inputs & small controls (`10pt`):** Search bar field and compact row highlights.
- **List cards & event tiles (`12pt`):** Merchant row press highlights, event carousel cards, info cards.
- **Selection cards (`14pt`):** Primary onboarding CTAs and city picker rows.
- **Grouped surfaces (`16pt`):** `PlaceGroupedSurface` cards in merchant and community detail views.
- **Overlay cards (`22pt`):** Feature hint tooltips.
- **Capsules (`9999pt`):** Filter chips, map control pills, and quick-action pills.
- **Container-hugging surfaces (iOS 26+):** Prefer `ConcentricRectangle()` when a custom shape sits directly against a screen or sheet edge so corners follow iPhone Duo's asymmetric outer display.

## Components

### Grouped Detail Surface (`PlaceGroupedSurface`)
Calm translucent card unifying related metadata (hours, address, contact, socials, reviews, trust/verify actions) in both `BusinessDetailView` and `CommunityDetailView`.
- **Corner Style:** `16pt` continuous squircle.
- **Background & Border:** `.regularMaterial` fill with `0.5pt` `Color(.separator).opacity(0.35)` stroke inside `.overlay { ... }`.
- **Padding:** `12pt` vertical × `14pt` horizontal (`6pt` vertical when stacking divider-separated interactive rows).
- **Implementation rule:** Stores built `Content` (never an escaping `@ViewBuilder` closure).

### Tactile Buttons & Rows (`TactilePressButtonStyle`, `TactileRowButtonStyle`, `TactileCopyButton`)
Responsive, subtle press affordances without loud color flashes.
- **Touch Target:** Strictly `≥ 44×44pt` on every tappable control (including icon-only clear-search buttons, copy buttons, and map controls).
- **Press State:** `0.97×` scale + `0.88` opacity for buttons; `0.985×` scale + `Color.primary.opacity(0.06)` fill for rows (`140ms`, opacity-only under Reduce Motion).
- **Copy Feedback (`TactileCopyButton`):** Morphs icon to checkmark + localized `"Copied"` pill with `.sensoryFeedback(.success, trigger: copied)`.

### Filter & Category Chips (`BusinessesListView`)
Fast, scannable single-tap utility filters (`Saved`, `Open Now`, `Lightning`, `NFC`, `Verified`) and merchant categories.
- **Layout:** Horizontal `ScrollView` with `.scrollIndicators(.hidden)`, or wrapping `BitLocalFlowLayout` inside detail cards.
- **States:** Inactive uses subtle neutral fill + `.primary` text; active uses `AccentColor` (`#FC780F`) fill + white text + `.sensoryFeedback(.selection)`.

### Search Bar (`BusinessesListView`, `CommunitiesListView`, `MerchantAlertCityPickerView`)
Compact, translucent search input docked cleanly at the top of the sheet/sidebar.
- **Controls:** Magnifying glass icon, native `TextField`, `44×44pt` labeled clear button (`Button("Clear search", systemImage: "xmark.circle.fill").labelStyle(.iconOnly)`), and Cancel action when focused.

### Navigation & Map Chrome (`IPhoneLayoutView`, `IPadLayoutView`, `MapButtonsView`)
Native system toolbars first, adapting cleanly between iPhone, iPad, and iPhone Duo's vertical outer-display rail.
- **Toolbar Items:** Always supply both title and SF Symbol (`Button("...", systemImage: "...")`) with `.primary` vibrancy so iPhone Duo vertical bars and overflow menus render icons and labels natively.
- **Navigation Stack:** Single value-based `NavigationStack(path: $viewModel.path)` routed through `BitLocalNavigationRoute` (never mixing destination-closure `NavigationLink` with `navigationDestination(for:)`).
- **Sheet Toolbar Exception:** `BottomSheetContentView` and `SettingsView` intentionally apply `disableVerticalToolbarIfAvailable()` (`toolbarVerticalBehavior(.disabled)` on iOS 27.1+) because the main map scene already owns the outer-display vertical bar on iPhone Duo.

### Settings & Secondary Modals (`SettingsView`, `AboutView`, `MerchantAlertsView`)
Native `List` / `Form` with `.insetGrouped` style, `LabeledContent` for picker/control pairs, and system navigation push for `AboutView` and `MerchantAlertsView`.

### Empty, Loading & Offline States
- **Empty & Error States:** Use native `ContentUnavailableView` (and `ContentUnavailableView.search` in searchable views) rather than hand-built placeholder stacks.
- **Offline Travel Mode Banner:** Compact `.regularMaterial` / subtle `.orange` notice in `BusinessesListView` when `NetworkReachabilityMonitor.isOffline` is true, clarifying that cached places and saved bookmarks remain browsable offline.

## Do's and Don'ts

### Do:
- **Do** enforce `≥ 44×44pt` hit areas and descriptive VoiceOver labels on every button, menu, picker, and icon control.
- **Do** use native SwiftUI modifiers (`foregroundStyle`, `clipShape(.rect(cornerRadius:))`, `toolbarVisibility`, `toolbarBackgroundVisibility`, `scrollIndicators(.hidden)`, builder `overlay { }` / `background { }`).
- **Do** route all `NavigationStack` pushes through `BitLocalNavigationRoute` and optional destinations through `.navigationDestination(item:)`.
- **Do** test size-class branching with `== .regular` and guard any iOS 27+ API with `#if compiler(>=6.4)` and `#available(iOS 27.x, *)`.
- **Do** keep conditional modifier values inside modifiers (with `AnyShapeStyle` when needed) so SwiftUI preserves structural view identity.
- **Do** run `./scripts/verify_design_conventions.sh` before pushing changes.

### Don't:
- **Don't** use `UIScreen.main` or `UIDevice.current.userInterfaceIdiom` for layout decisions.
- **Don't** introduce `View.if()` helpers, `_ConditionalContent` modifier branches, or appearance-keyed `.id(...)` modifiers that destroy navigation/scroll state.
- **Don't** hardcode `.font(.system(size: ...))`, use `.caption2` for readable text, or nest icon-in-circle repetition / ALL-CAPS eyebrows / pill soup.
- **Don't** use `.onTapGesture` for ordinary buttons—use `Button` so VoiceOver, Switch Control, and keyboard navigation work.
- **Don't** block the main thread with `DispatchSemaphore`, call `Task.sleep(nanoseconds:)`, or share unsynchronized `DateFormatter`s across threads.
- **Don't** silently swallow user-action errors (geocoding, CloudKit bookmark saves, search failures)—either queue durable offline retries or surface an alert.
