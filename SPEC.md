# BitLocal Product Specification

**Version:** 2.0.5 (Build 43)
**Last Updated:** December 29, 2025
**Platform:** iOS 17.0+

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Technical Architecture](#2-technical-architecture)
3. [Data Sources & Models](#3-data-sources--models)
4. [Core Features & User Flows](#4-core-features--user-flows)
5. [Data Management & Caching](#5-data-management--caching)
6. [UI/UX Design System](#6-uiux-design-system)
7. [Localization & Accessibility](#7-localization--accessibility)
8. [Permissions & Privacy](#8-permissions--privacy)
9. [Performance & Optimization](#9-performance--optimization)
10. [App Lifecycle Management](#10-app-lifecycle-management)
11. [Limitations & Known Issues](#11-limitations--known-issues)
12. [Future Enhancement Opportunities](#12-future-enhancement-opportunities)
13. [Build & Distribution](#13-build--distribution)
14. [Project Structure](#14-project-structure)
15. [Key Architectural Decisions](#15-key-architectural-decisions)
16. [Security Considerations](#16-security-considerations)

---

## 1. Product Overview

### Product Identity

**Name:** BitLocal
**Bundle Identifier:** app.bitlocal.bitlocal
**Team Identifier:** 5YUMLYCFT8
**Developer:** Brink 13 Labs (Joe Castagnaro)

### Purpose

BitLocal is an iOS application designed to help users discover and locate physical businesses that accept Bitcoin payments. The app provides an interactive map-based interface to find Bitcoin-accepting merchants near the user's location, displaying detailed business information including accepted payment methods (on-chain, Lightning Network, contactless Lightning).

### Target Users

- Bitcoin enthusiasts looking to spend Bitcoin at physical locations
- Merchants who want to discover Bitcoin-accepting businesses
- Travelers seeking Bitcoin-friendly establishments
- Anyone interested in supporting the circular Bitcoin economy

### Value Proposition

BitLocal bridges the gap between Bitcoin holders and the physical economy by making it easy to discover where Bitcoin is accepted as a payment method. The app prioritizes privacy, simplicity, and user experience.

---

## 2. Technical Architecture

### Platform Requirements

- **Platform:** iOS (Universal: iPhone and iPad)
- **Minimum Version:** iOS 17.0
- **Supported Orientations:**
  - iPhone: Portrait only
  - iPad: All orientations (landscape left, landscape right, portrait, portrait upside down)
- **App Category:** Lifestyle

### Technology Stack

- **Language:** Swift (100% SwiftUI)
- **Framework:** SwiftUI with iOS 17.0+ APIs
- **Architecture Pattern:** MVVM (Model-View-ViewModel)
- **Total Codebase:** ~8,125 lines of Swift code across 47 files
- **Mapping Framework:** MapKit (Apple Maps)
- **Location Services:** CoreLocation
- **Networking:** URLSession (native)
- **Dependencies:** Zero external dependencies (100% native iOS frameworks)
- **Package Management:** Swift Package Manager

### Architecture Pattern: MVVM

```
┌─────────────────┐
│     Views       │ ← SwiftUI Views (presentation layer)
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  ViewModels     │ ← Business logic, @Published state
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│     Models      │ ← Data structures, API responses
└─────────────────┘
```

**Benefits:**
- Clean separation of concerns
- Testable business logic
- SwiftUI-friendly reactive patterns
- Scalable for future features

---

## 3. Data Sources & Models

### Primary Data Source

**BTC Map API** (https://api.btcmap.org/v2/)

- RESTful API providing Bitcoin merchant data
- Data includes OpenStreetMap (OSM) tagged locations
- Incremental updates using timestamp-based queries
- Read-only access (no authentication required)

### Data Attribution

- **BTC Map:** Primary merchant database
- **OpenStreetMap:** Location and address data
- Both sources are credited in the app's UI

### Core Data Model: Element

The `Element` struct represents a Bitcoin-accepting business location:

```swift
struct Element: Identifiable, Codable {
    let id: String              // Unique identifier from BTC Map
    let uuid: UUID              // Local UUID for SwiftUI
    let osmJSON: OsmJSON?       // OpenStreetMap data
    let tags: Tags?             // BTC Map specific tags
    let createdAt: String       // ISO 8601 timestamp
    let updatedAt: String?      // Last modification timestamp
    let deletedAt: String?      // Soft delete timestamp
    var address: Address?       // Parsed/geocoded address
}
```

### OSM Tags Structure

**Location Data:**
- `lat`, `lon`: Geographic coordinates
- `geometry`: Point geometry
- `bounds`: Geographic bounding box

**Address Components:**
- `addr:housenumber`, `addr:street`
- `addr:city`, `addr:state`, `addr:postcode`
- `addr:country`

**Business Information:**
- `name`: Business name
- `operator`: Business operator
- `description`: Business description
- `website`: URL
- `phone`: Contact number
- `opening_hours`: OSM opening hours format

**Business Type:**
- `amenity`: Restaurant, cafe, bar, pub, fast_food, bank, atm, pharmacy, hospital, fuel, parking, etc.
- `shop`: Supermarket, convenience, bakery, clothes, electronics, etc.
- `tourism`: Hotel, hostel, guest_house, camp_site, museum, etc.
- `leisure`: Park, stadium, fitness_centre, swimming_pool, etc.
- `craft`: Brewery, winery, distillery, carpenter, tailor, etc.
- `healthcare`: Physiotherapist, optometrist, dentist, doctor, clinic
- `office`: Coworking_space, travel_agent

**Payment Methods:**
- `payment:bitcoin`: Generic Bitcoin acceptance
- `payment:onchain`: On-chain Bitcoin payments
- `payment:lightning`: Lightning Network payments
- `payment:lightning_contactless`: NFC Lightning payments

### Supported Business Categories

**75+ business types organized into groups:**

**Amenity:** Restaurants, cafes, bars, pubs, fast food, banks, ATMs, pharmacies, hospitals, fuel stations, parking, libraries, schools, theaters, cinemas, nightclubs

**Shop:** Supermarkets, convenience stores, bakeries, clothing, electronics, computers, mobile phones, hardware, furniture, florists, gifts, books, alcohol, pets, sports, bicycles, cars, beauty salons, hairdressers, jewelry

**Tourism:** Hotels, hostels, guest houses, camp sites, museums, galleries, tourist attractions

**Leisure:** Parks, stadiums, fitness centers, swimming pools, golf courses, sports centers

**Craft:** Breweries, wineries, distilleries, carpenters, tailors, shoemakers, jewelers

**Office:** Coworking spaces, travel agents

**Healthcare:** Physiotherapists, optometrists, dentists, doctors, clinics

**Custom:** User-defined categories for uncategorized businesses

---

## 4. Core Features & User Flows

### 4.1 Onboarding Experience

**First-Launch Onboarding Flow** (4 screens):

1. **Discover Bitcoin** - Introduction to finding Bitcoin merchants
2. **Map Navigation** - Explains map-based discovery
3. **Location Permission** - Optional location access request
4. **Ready to Explore** - Final call-to-action

**Features:**
- Adaptive UI for different device sizes (iPhone SE to iPad Pro)
- Beautiful animations and spring transitions
- Skippable location permission step
- Only shown once (flag persisted in UserDefaults)
- Can be re-triggered from About menu
- Dynamic sizing based on screen dimensions

**User Flow:**
```
App Launch → Check Onboarding Flag → [First Time]
    ↓
Screen 1 (Discover) → Screen 2 (Navigate) → Screen 3 (Location) → Screen 4 (Ready)
    ↓
Main App Interface
```

### 4.2 Map-Based Discovery (Primary Interface)

#### iPhone Layout

**Visual Structure:**
- Full-screen map with floating header
- Bottom sheet with 3 detents:
  - Small: ~30% height (business list preview)
  - Medium: ~50% height (expanded list)
  - Large: ~90% height (full list)
- Floating map buttons (location center, recenter)
- OpenStreetMap attribution link

**Interactions:**
- Drag bottom sheet to adjust detent
- Tap business in list → Navigate to detail + zoom map
- Tap map annotation → Show detail in bottom sheet
- Tap location button → Re-center map on user
- Tap attribution → Open OSM in Safari

#### iPad Layout

**Split-View Interface:**
- Left sidebar: Business list (35-40% width)
- Right panel: Full-screen map
- Settings as popover menu
- Persistent navigation structure
- No bottom sheet

**Interactions:**
- Tap business in list → Navigate to detail + zoom map
- Tap map annotation → Navigate to detail view
- Settings gear icon → Show popover
- Full keyboard navigation support

### 4.3 Map Features

**Visual Elements:**
- Custom Bitcoin-orange map markers
- Clustering of nearby locations
- SF Symbol icons based on business type (75+ unique symbols)
- User location indicator (blue dot)
- Map type support (Standard, Satellite, Hybrid)

**Behavior:**
- Auto-center on first location update
- Visible range: 25-mile radius from map center
- Dynamic annotation updates as map moves
- Smooth zoom to business when selected
- Efficient annotation clustering (MapKit automatic)

**Performance:**
- Debounced region changes (500ms)
- Annotation reuse pattern
- Only visible businesses loaded
- Background thread for calculations

### 4.4 Business List View

**Display:**
- Sorted by distance from user (closest first)
- Maximum 25 results displayed at once
- Real-time distance calculation
- Configurable distance units (Auto, Miles, Kilometers)

**Business Cell Information:**
- Business name (large, bold)
- Distance from user (with unit)
- Street address (number + street name)
- City, State, ZIP code
- Payment method icons:
  - Bitcoin symbol (₿) for generic Bitcoin
  - Lightning bolt for Lightning Network
  - Hand with lightning for contactless Lightning

**Interactions:**
- Tap business → Navigate to detail view + zoom map to location
- Automatic updates as map moves
- Empty state when no businesses in range

### 4.5 Business Detail View

**Comprehensive Information Display:**

**1. Header:**
- Business name (large title)
- Distance from user
- Back navigation

**2. Description Section** (if available):
- Full business description from OSM tags

**3. Business Details:**
- **Address** (tappable):
  - Full street address
  - City, State, ZIP, Country
  - Opens Apple Maps with directions
- **Website** (validated, tappable):
  - Opens in Safari
  - URL validation and formatting
- **Phone** (international support, tappable):
  - International format support
  - Opens Phone app to call
- **Opening Hours**:
  - Raw OSM format display
  - Future: Parse and humanize

**4. Payment Methods:**
- Clear indicators for:
  - Accepts Bitcoin (generic)
  - Accepts On-Chain Bitcoin
  - Accepts Lightning Network
  - Accepts Contactless Lightning (NFC)

**5. Mini Map:**
- Shows business location with custom marker
- Respects user's map type preference
- Centered and zoomed on business
- Non-interactive (tap to open full map)

**Adaptive Layout:**
- iPhone: Scrollable detail view
- iPad: Split-view detail panel
- Dynamic spacing based on content availability

### 4.6 Add Business to Map

**Multi-Step Submission Form** (5 progressive steps):

#### Step 1: Location

**Purpose:** Capture business location and address

**Fields:**
- Business name (required, text input)
- Street number (required, numeric)
- Street name (required, text input)
- City (required, text input)
- State/Province (required, text input)
- Country (required, text input)
- Postal code (optional, text input)
- Latitude/Longitude (auto-captured from map OR search)

**Features:**
- Location search functionality
- Interactive map preview
- Manual coordinate entry
- Real-time validation
- Auto-fill from search results

**Validation:**
- All required fields must be filled
- Valid coordinate format
- Enable "Continue" button when valid

#### Step 2: Details

**Purpose:** Business information and categorization

**Fields:**
- Business description (optional, multi-line text)
- Business category (required, picker):
  - 75+ predefined categories
  - "Other" option with custom text input
- Website (optional, validated URL)
- Phone number (optional, international format)
- OSM feature type (required, picker):
  - Amenity, Shop, Tourism, Leisure, Craft, Healthcare, Office

**Features:**
- Category-specific SF Symbol icons
- URL validation (must include protocol)
- International phone number support
- Smart keyboard types per field

**Validation:**
- Category and OSM type required
- URL format validation if provided
- Phone format validation if provided

#### Step 3: Payment Methods

**Purpose:** Specify accepted Bitcoin payment types

**Payment Options (toggles):**
- On-chain Bitcoin
- Lightning Network
- Contactless Lightning (NFC)

**Validation:**
- At least ONE payment method must be selected
- Cannot proceed without selection
- Visual indicator when invalid

#### Step 4: Opening Hours (Optional)

**Purpose:** Weekly schedule configuration

**Features:**
- Individual toggles for each day
- Time pickers for open/close times
- Supports different hours per day
- Consecutive day grouping
- Converts to OSM opening_hours format

**Days:**
- Monday through Sunday
- Each day independently configurable
- Default: 9:00 AM - 5:00 PM

**Output Format:**
- OSM standard: "Mo-Fr 09:00-17:00; Sa 10:00-16:00"
- Handles complex schedules
- Graceful degradation if not provided

#### Step 5: Review & Submit

**Purpose:** Final review and submission

**Submitter Information:**
- Name (required)
- Email (required, validated)
- Relationship to business:
  - Owner
  - Customer/Visitor

**Review Sections:**
- Location details with map
- Business information
- Payment methods
- Opening hours (if provided)

**Submission:**
- Generates pre-filled email to support@bitlocal.app
- Includes all business details in OSM tag format
- Includes coordinates and OSM map URL
- Adds check_date timestamp
- Fallback to mailto: URL if Mail app unavailable

**Email Template:**
```
Subject: New Business Submission - [Business Name]

Submitter: [Name]
Email: [Email]
Relationship: [Owner/Customer]

Business Details:
- Name: [Business Name]
- OSM Type: [amenity/shop/etc]
- Category: [Category]
- Description: [Description]
- Website: [URL]
- Phone: [Phone]

Address:
[Street Number] [Street Name]
[City], [State] [Postal Code]
[Country]

Coordinates: [Lat], [Lon]
OSM Map: https://www.openstreetmap.org/?mlat=[Lat]&mlon=[Lon]&zoom=18

Payment Methods:
- On-chain: [yes/no]
- Lightning: [yes/no]
- Contactless: [yes/no]

Opening Hours: [OSM format or "Not provided"]

Check Date: [YYYY-MM-DD]
```

**Form Management:**
- Multi-step progress indicator
- Back navigation preserves data
- Cancel confirmation dialog
- Field validation before navigation
- Clear error messaging

### 4.7 Settings & Preferences

**Available Settings:**

**1. Map Type:**
- Standard (default)
- Satellite
- Hybrid
- Persisted in UserDefaults
- Applied app-wide instantly

**2. Appearance Mode:**
- System (follows iOS setting)
- Light
- Dark
- App-wide theme application
- Immediate visual update

**3. Distance Units:**
- Auto (based on device locale)
- Miles
- Kilometers
- Affects all distance displays

**Access:**
- iPhone: Gear icon in header → Sheet presentation
- iPad: Gear icon → Popover menu

**Persistence:**
- All settings saved to UserDefaults
- Loaded on app launch
- Synced across app sessions

### 4.8 About / Information

**Structured Information Sections:**

**1. Contribute:**
- **Add Business to Map**
  - Opens multi-step submission form
  - Icon: Plus circle

**2. Support BitLocal** (US region only):
- **Donate via Strike**
  - Opens Strike payment link
  - Icon: Heart

**3. Contact:**
- **General Support** → support@bitlocal.app
- **Report a Bug** → support@bitlocal.app
- **Suggest a Feature** → support@bitlocal.app
- All open Mail app with pre-filled subject

**4. Socials:**
- **X/Twitter** → @bitlocal_app
  - Opens X app or web

**5. More from Brink 13 Labs:**
- **Bitcoin Live Price Chart**
  - Opens web app
- **Movemates: Move Together**
  - Opens US App Store listing

**6. Other:**
- **BitLocal Website** → bitlocal.app
- **Brink 13 Labs** → brink13labs.com
- **Privacy Policy** → GitHub repository
- **BTC Map** → btcmap.org
- **OpenStreetMap** → openstreetmap.org/copyright
- **Bitcoin Resources** → Jameson Lopp's resources

**7. Utilities:**
- **Show Onboarding Again**
  - Resets onboarding flag
  - Restarts onboarding on next launch

**Design:**
- Custom Phosphor icons (22 unique)
- Grouped list style
- External links open in Safari
- Email links open Mail app
- Region-specific content (US donation)

---

## 5. Data Management & Caching

### Local Caching Strategy

**File-Based Caching:**
- **Location:** App Caches directory
- **File:** elements.json
- **Format:** JSON array of Element objects
- **Size:** Variable (depends on data volume)

**Cache Behavior:**

**First Launch:**
1. No cache exists
2. Full data fetch from BTC Map API
3. Save to elements.json
4. Display on map

**Subsequent Launches:**
1. Load from elements.json (instant UI)
2. Display cached data immediately
3. Delay 5 seconds (initial launch only)
4. Fetch updates using `updated_since` parameter
5. Merge new/updated elements
6. Save merged data to cache
7. Refresh UI

**Cache Invalidation:**
- App version change → Clear cache, full fetch
- Manual deletion of cache file → Full fetch
- API errors → Continue with cached data

### Geocoding Cache

**LRU (Least Recently Used) Cache:**
- **Max Size:** 100 addresses
- **Storage:** geocoding_cache.json
- **Purpose:** Reduce redundant reverse geocoding API calls

**Behavior:**
- Check cache before geocoding
- Rate limit: 1 concurrent request
- Cache hit → Return immediately
- Cache miss → Geocode, then cache
- Smart merging of OSM + geocoded addresses

**Optimization:**
- Evict oldest entries when full
- Persist to disk for cross-session use
- Background thread for I/O operations

### Data Fetching Strategy

**API Endpoint:**
```
GET https://api.btcmap.org/v2/elements
Query Parameters:
  - updated_since: ISO 8601 timestamp (for incremental updates)
```

**Fetch Flow:**
```
App Launch
    ↓
Load Cache (if exists)
    ↓
Display Cached Data
    ↓
[Wait 5s on first launch]
    ↓
Fetch Updates (updated_since = last fetch time)
    ↓
Merge with Cached Data
    ↓
Filter Deleted Elements
    ↓
Save to Cache
    ↓
Update UI
```

**Active Use:**
- Map region changes → Update visible annotations
- Debounced updates (500ms)
- Only show businesses with valid names
- Exclude soft-deleted businesses (deletedAt != nil)
- 25-mile radius filter from map center

**Error Handling:**
- Network errors → Continue with cached data
- Parse errors → Log and continue
- Missing data → Graceful degradation

### Performance Optimizations

**Threading:**
- API calls: Background thread
- Cache I/O: Background thread
- UI updates: Main thread only
- Geocoding: Background thread (rate-limited)

**Memory Management:**
- LRU cache prevents unbounded growth
- Periodic cache cleanup on scene background
- Efficient annotation diffing (add/remove deltas only)
- Annotation clustering reduces memory

**Batching:**
- Merge all updates before UI refresh
- Single write to cache per fetch cycle
- Batched geocoding requests

---

## 6. UI/UX Design System

### Color Palette

**Primary Colors:**
- **Accent Color:** Bitcoin Orange (#F7931A)
  - Used for: Buttons, links, active states, map markers
- **Marker Color:** Custom orange tint for map annotations

**System Colors:**
- **Background:** System adaptive (light/dark mode)
- **Text Primary:** System adaptive
- **Text Secondary:** System adaptive with reduced opacity
- **Separator:** System adaptive

**Semantic Colors:**
- Success: System green
- Error: System red
- Warning: System orange

### Typography

**Custom Fonts:**
- **Fredoka Medium:** Headers, titles
- **Fredoka Variable Weight:** Dynamic weight adjustments
- **Ubuntu Light Italic:** Accent text
- **Ubuntu Medium Italic:** Subheadings

**System Fonts:**
- **SF Pro:** Body text, labels, buttons
- **SF Pro Rounded:** Numbers, stats

**Type Scale:**
- **Large Title:** 34pt (Fredoka)
- **Title:** 28pt
- **Title 2:** 22pt
- **Title 3:** 20pt
- **Headline:** 17pt (semibold)
- **Body:** 17pt
- **Callout:** 16pt
- **Subheadline:** 15pt
- **Footnote:** 13pt
- **Caption:** 12pt

**Dynamic Type:**
- Supports iOS accessibility text sizes
- Scales appropriately with user preferences
- Maintains hierarchy at all sizes

### Iconography

**Icon Libraries:**

**SF Symbols** (Apple's system icons):
- 75+ category-specific symbols for business types
- System UI elements (back, close, settings, etc.)
- Map controls (location, compass, etc.)
- Payment indicators (bitcoinsign, bolt.fill, etc.)

**Custom Phosphor Icons** (22 unique):
- About menu items
- Social media links
- Custom actions
- Imported as custom symbol assets

**Icon Sizes:**
- Small: 16x16pt
- Medium: 24x24pt
- Large: 32x32pt
- Map Markers: 30x30pt

**Icon Colors:**
- System: Follows tint color
- Accent: Bitcoin orange
- Hierarchical: System adaptive with layers

### Spacing & Layout

**Spacing Scale:**
- XXS: 4pt
- XS: 8pt
- S: 12pt
- M: 16pt
- L: 24pt
- XL: 32pt
- XXL: 48pt

**Layout Patterns:**

**iPhone:**
- Edge padding: 16pt
- Section spacing: 24pt
- List row height: 60-80pt (dynamic)
- Bottom sheet corner radius: 20pt

**iPad:**
- Edge padding: 24pt
- Section spacing: 32pt
- Sidebar width: 35-40% of screen
- Corner radius: 12pt

**Safe Area:**
- All views respect safe area insets
- Bottom sheet accounts for home indicator
- Navigation bars handled automatically

### Component Library

**Map Components:**
- `MapView`: Main map interface
- `AnnotationView`: Custom map markers
- `MapButtonsView`: Location/recenter buttons

**List Components:**
- `BusinessesListView`: Scrollable business list
- Business cell with distance/address/payments

**Detail Components:**
- `BusinessDetailView`: Full business information
- Mini map preview
- Action buttons (call, website, directions)

**Form Components:**
- Text fields with validation
- Toggles with labels
- Pickers with icons
- Time pickers
- Multi-step progress indicator

**Navigation:**
- Bottom sheet (iPhone)
- Split view (iPad)
- Modal presentations
- Popovers (iPad settings)

### Animations & Transitions

**Implemented:**
- Onboarding page transitions (spring animation, 0.4s)
- Bottom sheet detent changes (smooth easing)
- Map annotation clustering (automatic MapKit)
- Business cell fade-in on appear
- Settings popover scale + opacity transition
- Scene phase transitions (debounced)

**Animation Values:**
- Spring: Response 0.4, damping 0.8
- Ease In/Out: 0.3s
- Linear: 0.2s

**Performance:**
- 60 FPS target
- GPU-accelerated where possible
- Reduced motion support (future)

### Responsive Design

**Device Categories:**

**Compact (iPhone SE, iPhone 12 mini):**
- Tighter spacing
- Smaller fonts
- Single column layouts
- Reduced padding

**Regular (iPhone 13, 14, 15):**
- Standard spacing
- Default fonts
- Optimized layouts

**Large (iPhone Pro Max, Plus):**
- Generous spacing
- Larger touch targets
- More content visible

**iPad:**
- Split-view layouts
- Larger typography
- Multi-column where appropriate
- Keyboard navigation

**Adaptive Behaviors:**
- Onboarding: Scales content based on screen height
- Map: Adjusts button positions
- Lists: Adjusts row heights
- Forms: Keyboard avoidance

---

## 7. Localization & Accessibility

### Localization

**Current Status:** English (en-US) only

**Localization Architecture:**
- Uses `NSLocalizedString` throughout codebase
- 100+ localization keys defined
- Ready for .strings file implementation
- Keys structured hierarchically

**Key Categories:**
- Onboarding: "onboarding.page1.title", etc.
- Business Form: "form.location.title", etc.
- Settings: "settings.mapType.standard", etc.
- About: "about.section.contact", etc.
- Errors: "error.validation.required", etc.

**Future Languages (Priority):**
1. Spanish (es)
2. Portuguese (pt-BR)
3. German (de)
4. French (fr)
5. Japanese (ja)

**International Support:**
- Phone number formatting (international)
- Distance units (auto-detect by locale)
- Address formats (flexible)
- Date/time formatting (locale-aware)
- Currency: Bitcoin (universal, no conversion needed)

### Accessibility

**Implemented:**

**Dynamic Type:**
- All text uses SwiftUI's built-in scaling
- Maintains hierarchy at all sizes
- Tested up to XXXL sizes

**Color Contrast:**
- Meets WCAG AA standards
- High contrast mode support (system)
- Color is not the only indicator

**Touch Targets:**
- Minimum 44x44pt for all interactive elements
- Increased padding on critical actions
- Clear focus states

**Semantic Structure:**
- Proper heading hierarchy
- Grouped related elements
- Clear navigation structure

**VoiceOver Considerations:**
- Buttons have descriptive labels
- Images have alt text (where applicable)
- Forms have field labels
- Error messages are announced

**Needs Improvement:**
- VoiceOver hints for map interactions
- Accessibility labels for custom icons
- Larger tap targets for map buttons
- Better keyboard navigation on iPad
- Testing with VoiceOver users
- Haptic feedback for important actions

**Future Enhancements:**
- Reduce motion support
- Bold text support
- Button shapes mode
- Closed captions (if video added)

---

## 8. Permissions & Privacy

### Required Permissions

**Location Services (When In Use Only):**
- **Purpose String:** "BitLocal asks for your location to find businesses near you. Location sharing is not required to use BitLocal."
- **When Requested:** During onboarding (Step 3)
- **Optional:** Yes, app fully functional without location
- **Usage:**
  - Find businesses near user
  - Calculate distances
  - Auto-center map
  - Never transmitted to servers
- **Fallback:** Manual map navigation if denied

**No Other Permissions Required:**
- No camera access
- No photo library access
- No microphone access
- No contacts access
- No notifications
- No background location

### Privacy Features

**Zero Tracking:**
- No analytics SDKs (Google, Firebase, Mixpanel, etc.)
- No advertising SDKs
- No crash reporting (except Apple's opt-in)
- No third-party tracking

**Data Collection:**
- **User Data:** None collected
- **Location:** Processed locally only, never transmitted
- **Usage Stats:** Not collected
- **Device Info:** Not collected
- **Submissions:** Voluntary, via user's email app

**No Accounts:**
- No user accounts or authentication
- No sign-up or login required
- Fully anonymous usage
- No user profiles

**No Monetization:**
- No ads
- No in-app purchases
- No subscriptions
- Free and open

**Privacy Policy:**
- URL: https://github.com/joeycast/BitLocal.app/blob/main/Privacy_Policy.md
- Accessible from About page
- Plain language
- Transparent about data usage

### Data Handling

**Local Data:**
- Preferences: UserDefaults (device-local)
- Cache: File system (app sandbox)
- Geocoding cache: File system (app sandbox)
- Never synced to cloud
- Deleted when app is deleted

**Network Requests:**
- **BTC Map API:**
  - Read-only
  - No authentication
  - No user identifiers
  - HTTPS only
- **Apple Geocoding:**
  - Standard iOS service
  - Apple's privacy policy applies
- **No Other Services**

**Submissions:**
- Sent via user's email app
- User controls what is sent
- User's email address (intentionally shared)
- No automatic submission
- Manual review by BitLocal team

---

## 9. Performance & Optimization

### App Performance Targets

**Launch Time:**
- **Cold Start:** < 2-3 seconds (with cached data)
- **Warm Start:** < 1 second
- **Time to Interactive:** < 3 seconds

**Responsiveness:**
- **UI Response:** < 100ms for all interactions
- **Map Panning:** 60 FPS
- **List Scrolling:** 60 FPS
- **Search Results:** < 500ms

**Memory:**
- **Base Memory:** ~50-80 MB
- **Peak Memory:** < 200 MB
- **Cache Size:** Variable (5-15 MB typical)

### Memory Management

**Caching Strategies:**
- LRU cache for addresses (max 100 entries)
- Bounded element cache (full dataset, but filtered)
- Automatic eviction when memory warnings
- Periodic cleanup on background

**Annotation Management:**
- Annotation reuse pattern (dequeue)
- Clustering reduces total annotations
- Add/remove only deltas (not full replacement)
- Efficient coordinate comparisons

**Background Processing:**
- API calls on background thread
- Cache I/O on background thread
- Geocoding rate-limited and backgrounded
- Main thread only for UI updates

### Network Optimization

**API Efficiency:**
- Incremental updates (not full re-fetch)
- Timestamp-based queries (`updated_since`)
- HTTPS with HTTP/2 support
- Gzip compression supported

**Request Patterns:**
- Initial: Full fetch (~2-5 MB typical)
- Updates: Incremental (~few KB typical)
- Frequency: On app launch + when needed
- No polling or background refresh

**Caching:**
- Aggressive local caching
- Offline mode fallback
- Cache-first strategy
- Network-second for updates

**Error Handling:**
- Retry logic with exponential backoff
- Graceful degradation on failure
- Continue with cached data on errors

### Map Performance

**Rendering Optimization:**
- Annotation clustering (automatic MapKit)
- Visible region limiting (25-mile radius)
- Debounced region changes (500ms)
- Efficient coordinate math

**Interaction Performance:**
- Tap response < 100ms
- Smooth zoom animations
- No dropped frames during pan/zoom
- Background thread for calculations

**Data Loading:**
- Lazy loading of annotations
- Only visible businesses loaded
- Distance calculations cached
- Geocoding cached and rate-limited

### Debug Logging

**Debug Modes:**
- 🔍 General: High-level flow logs
- 🌐 API: Network requests and responses
- 💾 Cache: Cache operations and hits/misses
- 🗺️ Map: Annotation updates and region changes

**Production:**
- All debug logging disabled
- Zero console output
- Minimal overhead
- No sensitive data logged

**Debug Build:**
- Verbose logging enabled
- Performance markers
- Network traffic logging
- Cache statistics

---

## 10. App Lifecycle Management

### Scene Phase Handling

**SwiftUI Scene Phases:**

**Active:**
- Normal operation
- All updates enabled
- Location tracking active
- Map updates in real-time
- Network requests allowed

**Inactive:**
- Transitioning state
- Minimal updates
- Location tracking continues
- No new network requests
- UI locked

**Background:**
- App in background
- Save state to disk
- Pause location updates
- Cancel in-flight requests
- Preserve scroll position

**Optimization:**
- Skip map updates when inactive/background
- Debounce rapid phase changes (2-second threshold)
- Save geocoding cache on background entry
- Smart data fetching on return to active:
  - If < 30 seconds in background: No fetch
  - If > 30 seconds: Fetch updates

### State Persistence

**Persisted Across Sessions:**
- Map type preference (UserDefaults)
- Appearance mode (UserDefaults)
- Distance unit (UserDefaults)
- Onboarding completion flag (UserDefaults)
- Last data update timestamp (UserDefaults)
- Elements cache (File system)
- Geocoding cache (File system)

**Not Persisted:**
- Map position/zoom level
- Selected business
- Bottom sheet detent state
- Scroll position in lists
- Search state (not implemented)
- Form data (intentionally cleared)

**State Restoration:**
- On relaunch: Load preferences
- Load cached data immediately
- Restore map to user's last location
- Restore settings selections
- Clear transient state (selections, navigation)

### Memory Warnings

**Response Strategy:**
1. Clear geocoding cache
2. Clear unused map annotations
3. Release cached images (if any)
4. Garbage collect unused elements
5. Force compact cache files

**Prevention:**
- Bounded caches (LRU)
- Efficient data structures
- Minimal object retention
- Regular cleanup cycles

---

## 11. Limitations & Known Issues

### Current Limitations

**Search & Discovery:**
1. ❌ No text-based business search
2. ❌ No filter by payment method
3. ❌ No filter by business category
4. ❌ No sort options (only distance)
5. ❌ 25-mile visible radius limitation
6. ❌ 25 business maximum in list view
7. ❌ No favorites or bookmarking

**Business Information:**
8. ❌ Opening hours shown as raw OSM string (not parsed)
9. ❌ No "Open Now" status indicator
10. ❌ No business photos
11. ❌ No user reviews or ratings
12. ❌ No social media links (beyond OSM data)
13. ❌ No business verification badge

**Functionality:**
14. ❌ No offline mode (requires initial data fetch)
15. ❌ No turn-by-turn navigation (external only)
16. ❌ No Apple Maps/Google Maps integration beyond opening
17. ❌ No sharing businesses with friends
18. ❌ No check-in or visit tracking

**Submissions:**
19. ❌ Email-only submission (no API integration)
20. ❌ No submission status tracking
21. ❌ No edit existing business feature
22. ❌ No photo upload with submissions

**Localization:**
23. ❌ English only (no other languages)
24. ❌ No region-specific features beyond distance units

**Platform:**
25. ❌ iOS only (no Android, web, or desktop)
26. ❌ No Apple Watch companion app
27. ❌ No widgets
28. ❌ No Live Activities

### Known Technical Issues

**Performance:**
- Large datasets (10,000+ businesses) may cause slow initial load
- Geocoding can be slow on poor network
- Map can lag with 100+ visible annotations

**UI/UX:**
- Bottom sheet can be finicky on iPhone SE
- iPad split view doesn't remember size preference
- Long business names truncate awkwardly
- Some SF Symbols not optimal for all categories

**Data:**
- Stale cache not automatically refreshed (requires app relaunch)
- Deleted businesses may briefly appear after deletion
- Geocoded addresses sometimes less accurate than OSM data
- Opening hours format can be confusing to users

**Edge Cases:**
- No location permission + no manual navigation = poor UX
- Businesses at exactly (0,0) coordinates ignored (likely invalid)
- Very long addresses overflow UI
- International phone numbers not always formatted correctly

### Technical Debt

1. **No Unit Tests:** Zero test coverage
2. **No UI Tests:** No automated testing
3. **Localization:** All strings in code, not .strings files
4. **Accessibility:** Limited VoiceOver testing
5. **Error Handling:** Basic error handling, could be more robust
6. **State Management:** Could benefit from Combine or async/await refactor
7. **Documentation:** Limited inline documentation
8. **Code Comments:** Minimal explanatory comments

---

## 12. Future Enhancement Opportunities

### High Priority

**Search & Filters** (High Impact, Medium Effort):
- Text search for business names
- Filter by payment methods (on-chain, Lightning, contactless)
- Filter by business categories
- Filter by "Open Now"
- Sort options: Distance, Name, Recently Added, Rating
- Search history

**Improved Business Hours** (High Impact, Low Effort):
- Parse OSM opening_hours format
- Display human-friendly schedule
- "Open Now" badge
- "Opens at X" or "Closes at X" indicators
- Today's hours highlighted
- Holiday hours support

**Offline Mode** (High Impact, High Effort):
- Full offline map tiles (MapKit snapshot API)
- Complete data cache for offline viewing
- Background sync when online returns
- Offline indicator in UI
- Queue submissions for when online

**Favorites & History** (Medium Impact, Low Effort):
- Bookmark favorite businesses
- Recently viewed businesses
- Visited locations tracking
- Custom lists/collections
- iCloud sync for favorites

### Medium Priority

**Direct BTC Map Integration** (High Impact, High Effort):
- API integration for submissions
- In-app submission status tracking
- Edit existing businesses (with permissions)
- Report incorrect information
- Verify business information
- Claim business ownership

**Enhanced Business Details** (Medium Impact, Medium Effort):
- Upload/view business photos
- User reviews and ratings
- Tips and recommendations
- Social media links (from OSM)
- Business verification badges
- "Verified by owner" status
- Additional payment details (wallet addresses, Lightning addresses)

**Navigation Integration** (Medium Impact, Low Effort):
- Turn-by-turn directions integration
- Apple Maps deep linking
- Google Maps option
- Walking/driving time estimates
- Public transit options
- AR walking directions (iOS 17+)

**Localization** (Medium Impact, Medium Effort):
- Spanish (es)
- Portuguese (pt-BR)
- German (de)
- French (fr)
- Japanese (ja)
- Proper .strings file structure
- Region-specific features
- Locale-aware formatting

**Improved Discovery** (Low Impact, Medium Effort):
- Remove 25-business limit with pagination
- Remove 25-mile radius limit (with performance consideration)
- Nearby categories carousel
- "Explore" mode with curated lists
- Trending/popular businesses
- New businesses section

### Low Priority

**Social Features** (Low Impact, High Effort):
- Share businesses via system share sheet
- User profiles (optional accounts)
- Check-ins at businesses
- Social feed of check-ins
- Follow friends
- Business recommendations based on friends

**Apple Watch App** (Low Impact, High Effort):
- Nearby businesses on wrist
- Quick directions
- "Pay here" reminder
- Check-in from watch
- Complications

**Widgets** (Medium Impact, Medium Effort):
- Home screen widget showing nearby count
- Small: Nearest business
- Medium: 3 nearby businesses
- Large: Map with nearby businesses
- Lock screen widget: Distance to nearest

**Live Activities** (Low Impact, Medium Effort):
- Navigation to business with ETA
- Dynamic Island support for directions
- "Approaching business" notification

**Advanced Features** (Variable Impact, High Effort):
- Augmented Reality business finder
- Apple Vision Pro spatial experience
- Siri integration ("Find Bitcoin businesses nearby")
- Shortcuts support
- Push notifications (opt-in)
- In-app messaging with businesses
- Lightning payment integration (pay at business)
- Bitcoin rewards/loyalty program

**Platform Expansion** (High Impact, Very High Effort):
- Android app
- Web app (Progressive Web App)
- macOS app (Mac Catalyst)
- watchOS standalone app
- visionOS native app

### Analytics & Insights (Future)

**Privacy-Preserving Analytics:**
- On-device only analytics
- No user tracking
- Aggregate usage patterns
- Popular categories
- Geographic distribution insights
- Privacy-first approach (no third parties)

---

## 13. Build & Distribution

### Build Configuration

**Bundle Information:**
- **Display Name:** BitLocal
- **Bundle Identifier:** app.bitlocal.bitlocal
- **Version:** 2.0.5
- **Build Number:** 43
- **Team ID:** 5YUMLYCFT8
- **Category:** Lifestyle

**Capabilities & Entitlements:**
- Location Services (When In Use)
- No other special entitlements
- No App Groups
- No iCloud
- No Push Notifications
- No Sign in with Apple

**Build Settings:**
- **Deployment Target:** iOS 17.0
- **Swift Version:** 5.9+
- **Supported Devices:** Universal (iPhone + iPad)
- **Orientations:**
  - iPhone: Portrait
  - iPad: All (landscape left/right, portrait, portrait upside down)
- **Requires Full Screen:** No (supports multitasking)

**Assets:**
- **App Icon:** 1024x1024 required
- **Launch Screen:** SwiftUI-based (no storyboard)
- **Custom Symbols:** 22 Phosphor icons
- **Custom Fonts:** 4 font files embedded

**Info.plist Keys:**
- `NSLocationWhenInUseUsageDescription`: Location permission
- `UIApplicationSceneManifest`: Scene-based lifecycle
- `UISupportedInterfaceOrientations`: Device-specific
- `UILaunchScreen`: SwiftUI launch screen
- `UIAppFonts`: Custom font registration

### Distribution Strategy

**Current Distribution:** Not specified in codebase

**Recommended Channels:**
1. **App Store** (Primary):
   - Public release
   - Worldwide availability
   - Category: Lifestyle > Travel or Finance
   - Age rating: 4+ (no sensitive content)
   - Pricing: Free

2. **TestFlight** (Beta Testing):
   - Internal testing (Brink 13 Labs team)
   - External testing (beta users)
   - Up to 10,000 external testers
   - 90-day beta cycles

3. **GitHub** (Open Source - if applicable):
   - Source code repository
   - Issue tracking
   - Community contributions
   - Documentation

**App Store Optimization:**

**Title:** BitLocal - Bitcoin Merchants

**Subtitle:** Find places that accept Bitcoin

**Keywords:**
- bitcoin
- lightning network
- bitcoin merchants
- crypto payments
- btcmap
- bitcoin accepted here
- spend bitcoin
- bitcoin nearby
- bitcoin stores
- bitcoin atm

**Description:**
```
Discover businesses that accept Bitcoin payments near you.

BitLocal helps you find physical locations that accept Bitcoin, including on-chain payments, Lightning Network, and contactless Lightning (NFC).

Features:
• Interactive map of Bitcoin-accepting businesses
• Filter by payment method
• Detailed business information
• Directions to any location
• Submit new businesses to the map
• Privacy-focused (no tracking or accounts)
• Powered by BTC Map and OpenStreetMap data

Whether you're looking to spend Bitcoin at a coffee shop, restaurant, hotel, or any other business, BitLocal makes it easy to support the circular Bitcoin economy.

100% free, no ads, no tracking.
```

**Screenshots:**
- iPhone 6.7": 5-6 screenshots
- iPhone 6.5": Same aspect ratio
- iPad Pro 12.9": 4-5 screenshots
- Focus on: Map view, business list, business detail, submission form, settings

**Privacy Label:**
- Data Not Collected
- Location: Used for functionality, not sent to servers
- Contact Info: Only for support emails (user-initiated)

**App Store Categories:**
- Primary: Lifestyle
- Secondary: Travel or Navigation

---

## 14. Project Structure

```
bitlocal/
├── Assets.xcassets/                # Visual assets
│   ├── AppIcon.appiconset          # App icon (all sizes)
│   ├── AccentColor.colorset        # Bitcoin orange accent
│   ├── MarkerColor.colorset        # Custom map marker tint
│   └── Symbols/                    # 22 custom Phosphor icons
│       ├── Plus.symbolset
│       ├── Heart.symbolset
│       ├── EnvelopeSimple.symbolset
│       ├── Bug.symbolset
│       ├── Lightbulb.symbolset
│       ├── XLogo.symbolset
│       ├── Globe.symbolset
│       ├── ShieldCheck.symbolset
│       ├── MapPin.symbolset
│       ├── Copyright.symbolset
│       ├── BookOpen.symbolset
│       ├── ChartLine.symbolset
│       ├── UsersThree.symbolset
│       ├── CodeBlock.symbolset
│       ├── At.symbolset
│       ├── Eye.symbolset
│       └── ...
│
├── Businesses/                     # Business domain
│   ├── Models/
│   │   ├── Element.swift              # Core business model (570 lines)
│   │   ├── BusinessSubmission.swift   # Submission form model
│   │   ├── BusinessHours.swift        # Hours data structure
│   │   ├── ElementCategorySymbols.swift  # Category icon mapping
│   │   └── BusinessSubmissionStep.swift  # Form step enum
│   ├── ViewModels/
│   │   └── BusinessSubmissionViewModel.swift  # Form state management
│   └── Views/
│       ├── AddBusinessFormView.swift        # Multi-step form container
│       ├── BusinessDetailView.swift         # Detail view (200+ lines)
│       ├── BusinessesListView.swift         # List of businesses
│       ├── LocationSearchView.swift         # Step 1: Location
│       ├── BusinessDetailsView.swift        # Step 2: Details
│       ├── BusinessPaymentsView.swift       # Step 3: Payments
│       ├── BusinessHoursView.swift          # Step 4: Hours
│       └── ReviewSubmissionView.swift       # Step 5: Review
│
├── Map/                            # Map functionality
│   ├── Models/
│   │   └── Annotation.swift           # Map annotation model
│   └── Views/
│       ├── MapView.swift              # Main map view
│       ├── IPhoneLayoutView.swift     # iPhone layout (bottom sheet)
│       ├── IPadLayoutView.swift       # iPad layout (split view)
│       ├── MapButtonsView.swift       # Location/recenter buttons
│       └── AnnotationView.swift       # Custom marker view
│
├── Settings/                       # Settings & preferences
│   ├── Models/
│   │   ├── Appearance.swift           # Appearance mode enum
│   │   ├── DistanceUnit.swift         # Distance unit enum
│   │   └── AppearanceManager.swift    # Theme manager
│   └── Views/
│       ├── CompactSettingsPopoverView.swift  # Settings popover
│       └── SettingsButtonView.swift          # Settings gear button
│
├── Shared/                         # Shared/common code
│   ├── ViewModels/
│   │   └── ContentViewModel.swift     # Main app view model (1200+ lines)
│   ├── Views/
│   │   ├── RootView.swift             # App root
│   │   ├── ContentView.swift          # Main content container
│   │   ├── MainView.swift             # Main interface
│   │   ├── AboutView.swift            # About/info page (500+ lines)
│   │   └── LoadingScreenView.swift    # Initial loading
│   └── Helpers/
│       ├── BtcMapCall.swift           # API manager (300+ lines)
│       ├── Extensions.swift           # Swift extensions (500+ lines)
│       ├── Debug.swift                # Debug logging utilities
│       ├── LRUCache.swift             # LRU cache implementation
│       └── MailComposer.swift         # Email composition helper
│
├── Onboarding/                     # First-run experience
│   └── Views/
│       └── OnboardingView.swift       # 4-screen onboarding (400+ lines)
│
├── Fonts/                          # Custom typography
│   ├── Fredoka-Medium.ttf
│   ├── Fredoka-VariableFont_wdth,wght.ttf
│   ├── Ubuntu-LightItalic.ttf
│   └── Ubuntu-MediumItalic.ttf
│
├── Resources/                      # Additional resources
│   └── (Empty or future assets)
│
├── bitlocalApp.swift               # App entry point (@main)
├── Package.swift                   # Swift package manifest
├── Info.plist                      # App configuration
├── LICENSE                         # Open source license
└── README.md                       # Project documentation

Total Swift Files: 47
Total Lines of Code: ~8,125 (excluding comments/whitespace)
External Dependencies: 0 (100% native iOS)
```

### Key File Descriptions

**Largest Files:**
- `ContentViewModel.swift` (~1200 lines): Main app state, data fetching, map logic
- `Element.swift` (~570 lines): Complete business model with all OSM tags
- `AboutView.swift` (~500 lines): About page with all sections and links
- `Extensions.swift` (~500 lines): Swift extensions for String, Date, CLLocationCoordinate2D, etc.
- `OnboardingView.swift` (~400 lines): 4-screen onboarding with animations
- `BtcMapCall.swift` (~300 lines): API manager with caching
- `BusinessDetailView.swift` (~200 lines): Business detail UI

**Critical Files:**
- `bitlocalApp.swift`: App lifecycle, scene configuration
- `ContentViewModel.swift`: Core app logic and state
- `BtcMapCall.swift`: All network and caching logic
- `Element.swift`: Data model that drives everything
- `MapView.swift`: Primary user interface

---

## 15. Key Architectural Decisions

### Why MVVM Architecture?

**Decision:** Use MVVM (Model-View-ViewModel) pattern

**Rationale:**
- **Clean Separation:** Views handle presentation, ViewModels handle logic, Models handle data
- **Testability:** Business logic in ViewModels is testable without UI
- **SwiftUI-Friendly:** `@Published` properties integrate seamlessly with SwiftUI
- **Scalability:** Easy to add features without tangling concerns
- **Maintainability:** Clear structure makes code easier to understand

**Trade-offs:**
- More files/boilerplate than simple MVVM
- Learning curve for new contributors
- Can be over-engineered for simple views

**Alternatives Considered:**
- **MVC:** Too much logic in ViewControllers (not applicable to SwiftUI)
- **Redux/TCA:** Too complex for current app scope
- **VIPER:** Over-engineered for app size

---

### Why Zero External Dependencies?

**Decision:** Use only native iOS frameworks, no SPM/CocoaPods packages

**Rationale:**
- **Smaller App Size:** No bloated frameworks
- **Faster Compile Times:** Fewer dependencies to build
- **No Version Conflicts:** No dependency hell
- **Security:** No third-party vulnerabilities
- **Longevity:** No abandoned dependency risk
- **Privacy:** No tracking from third parties
- **Learning:** Forces understanding of native APIs

**Trade-offs:**
- More code to write manually
- Miss some nice-to-have features
- Reinventing some wheels (e.g., LRU cache)

**Alternatives Considered:**
- **Alamofire:** Native URLSession is sufficient
- **Kingfisher:** Not needed (no image loading currently)
- **SnapKit:** SwiftUI handles layout
- **SwiftLint:** Could add for code quality

---

### Why File-Based Caching?

**Decision:** Use JSON files in Caches directory, not UserDefaults or Core Data

**Rationale:**
- **Storage Capacity:** UserDefaults has size limits (~1MB recommended)
- **Performance:** Faster for large datasets than Core Data
- **Simplicity:** Codable makes JSON encoding trivial
- **Easy Management:** Can inspect/clear cache files easily
- **No Schema:** No migration complexity like Core Data
- **Automatic Cleanup:** iOS can purge Caches directory if needed

**Trade-offs:**
- No automatic iCloud sync
- Manual cache invalidation logic
- No query capabilities (must load all data)

**Alternatives Considered:**
- **UserDefaults:** Too small for thousands of businesses
- **Core Data:** Over-engineered for simple caching
- **SQLite:** More complex than needed
- **Realm:** External dependency

---

### Why Email-Based Submissions?

**Decision:** Submit new businesses via pre-filled email, not direct API integration

**Rationale:**
- **No Backend Needed:** BTC Map doesn't have write API for public use
- **Manual Review:** Ensures quality and prevents spam
- **User Control:** Users see exactly what's being sent
- **Privacy:** No accounts or authentication required
- **Simplicity:** Less code, fewer edge cases
- **Transparency:** User's email is intentionally included

**Trade-offs:**
- No instant feedback on submission status
- Manual processing required
- Depends on user having Mail app configured
- Can't track submission in-app

**Alternatives Considered:**
- **Direct API:** BTC Map doesn't offer public write access
- **Custom Backend:** Too much infrastructure for MVP
- **Forms/Submissions Service:** Adds dependency and cost
- **In-App Webview:** Less transparent, worse UX

---

### Why iOS 17.0 Minimum?

**Decision:** Target iOS 17.0 as minimum deployment target

**Rationale:**
- **Modern SwiftUI:** Access to latest SwiftUI features
- **NavigationStack:** Better navigation than NavigationView
- **Performance:** iOS 17 SwiftUI is significantly faster
- **MapKit:** Latest MapKit features and clustering
- **User Base:** ~70-80% of users on iOS 17+ within months
- **Development Speed:** Fewer workarounds for old OS bugs
- **Smaller codebase:** No compatibility shims

**Trade-offs:**
- Excludes users on older devices (iPhone X, 8, etc.)
- Smaller potential audience
- Can't reach users who don't update

**Alternatives Considered:**
- **iOS 15.0:** Much larger user base, but many SwiftUI bugs
- **iOS 16.0:** Could work, but iOS 17 has NavigationStack improvements
- **iOS 18.0:** Too cutting-edge, excludes too many users

---

### Why MapKit over Google Maps?

**Decision:** Use Apple MapKit instead of Google Maps SDK

**Rationale:**
- **Native Integration:** Perfect integration with iOS
- **No API Keys:** No quota limits or billing
- **Privacy:** No Google tracking
- **Performance:** GPU-accelerated, optimized for iOS
- **Consistency:** Matches system Maps app
- **Clustering:** Built-in annotation clustering
- **Zero Dependencies:** No external SDK

**Trade-offs:**
- Less detailed maps in some regions
- Fewer customization options
- No Street View equivalent
- Less familiar to Android users

**Alternatives Considered:**
- **Google Maps:** More detailed, but requires API key and tracking
- **Mapbox:** Beautiful, but costs money and external dependency
- **OpenStreetMap Tiles:** Complex to implement and host

---

### Why SwiftUI over UIKit?

**Decision:** 100% SwiftUI, zero UIKit

**Rationale:**
- **Modern Development:** SwiftUI is the future of iOS development
- **Less Code:** Declarative UI requires less boilerplate
- **Live Preview:** Xcode previews speed up development
- **Cross-Platform:** Easier to port to macOS/watchOS/visionOS
- **State Management:** @Published, @State, @Binding simplify state
- **Animations:** Built-in animation system is powerful and simple

**Trade-offs:**
- Some advanced features require UIKit (via UIViewRepresentable)
- Debugging can be harder (especially layout)
- Less Stack Overflow answers for edge cases
- Performance can be unpredictable in complex views

**Alternatives Considered:**
- **UIKit:** More mature, but verbose and tedious
- **Hybrid:** Adds complexity, not needed for this app

---

## 16. Security Considerations

### Data Security

**No Sensitive Data Stored:**
- No user passwords or credentials
- No payment information
- No API keys or tokens
- No personally identifiable information (PII)
- Location never stored long-term

**Network Security:**
- All requests over HTTPS
- Certificate pinning not needed (public API)
- No authentication tokens to leak
- No user session management

**Data Validation:**
- All form inputs validated before use
- URL validation prevents malicious links
- Email format validation
- Phone number format validation
- Coordinate bounds checking

### Code Security

**No Dynamic Code Execution:**
- No `eval()` or similar
- No web views with user-generated content
- No third-party JavaScript
- No deep link parsing vulnerabilities

**Input Sanitization:**
- All user inputs sanitized for email composition
- Special characters handled safely
- SQL injection not applicable (no SQL database)
- XSS not applicable (no web content)

**Safe External Links:**
- All URLs validated before opening
- Safari View Controller for external web content
- System apps (Mail, Phone, Maps) handle their own security

### Privacy & Tracking

**Zero Tracking:**
- No analytics SDKs (Google Analytics, Firebase, Mixpanel, etc.)
- No advertising SDKs (AdMob, Facebook Ads, etc.)
- No crash reporting beyond Apple's opt-in
- No user behavior tracking
- No device fingerprinting

**Location Privacy:**
- Location never leaves the device
- No location uploaded to servers
- Used only for local calculations
- Optional permission (app works without it)
- "When In Use" only (not background tracking)

**No Third Parties:**
- Only Apple services (Maps, Mail, Safari)
- BTC Map API (read-only, no user data sent)
- No cross-site tracking
- No data brokers

### Vulnerability Mitigation

**Common Vulnerabilities:**
- **Injection Attacks:** N/A (no database, no eval)
- **XSS:** N/A (no web content)
- **CSRF:** N/A (no authenticated sessions)
- **Man-in-the-Middle:** HTTPS only, Apple's App Transport Security
- **Data Exposure:** No sensitive data to expose
- **Broken Authentication:** N/A (no authentication)
- **Security Misconfiguration:** Minimal configuration surface

**App Store Security:**
- Code signing required (Team ID: 5YUMLYCFT8)
- App Review process catches obvious issues
- Sandboxed environment
- Capabilities strictly scoped

### Future Security Enhancements

**Recommended:**
- Add Content Security Policy if web views added
- Implement certificate pinning if handling payments
- Add biometric authentication if accounts added
- Penetration testing for public release
- Security audit of submission workflow
- Rate limiting on API calls (client-side)

**Not Needed:**
- Encryption at rest (no sensitive data)
- Secure enclave (no credentials)
- Two-factor authentication (no accounts)
- OAuth/OpenID (no third-party login)

---

## Appendix A: API Reference

### BTC Map API

**Base URL:** `https://api.btcmap.org/v2/`

**Endpoints Used:**

#### GET /elements

Fetch all Bitcoin-accepting business elements.

**Query Parameters:**
- `updated_since` (optional): ISO 8601 timestamp
  - Returns only elements updated after this time
  - Used for incremental updates

**Response:**
```json
[
  {
    "id": "node:123456789",
    "osm_json": {
      "tags": {
        "name": "Bitcoin Coffee Shop",
        "amenity": "cafe",
        "payment:bitcoin": "yes",
        "payment:lightning": "yes",
        "addr:street": "Main St",
        "addr:housenumber": "123",
        "addr:city": "San Francisco",
        "addr:state": "CA",
        "addr:postcode": "94102",
        "website": "https://example.com",
        "phone": "+1-415-555-0123",
        "opening_hours": "Mo-Fr 08:00-18:00"
      },
      "lat": 37.7749,
      "lon": -122.4194
    },
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-06-20T14:22:00Z",
    "deleted_at": null
  }
]
```

**Rate Limiting:** Not specified, but app uses responsible caching

**Attribution Required:** Yes, BTC Map and OpenStreetMap

---

## Appendix B: Glossary

**BTC Map:** Open-source database of Bitcoin-accepting businesses worldwide

**Element:** A business location in the BTC Map database

**Lightning Network:** Layer-2 Bitcoin payment protocol for instant, low-fee transactions

**On-Chain:** Traditional Bitcoin transactions recorded on the blockchain

**Contactless Lightning:** NFC-enabled Lightning payments (tap-to-pay)

**OSM (OpenStreetMap):** Open-source, community-driven map database

**OSM Tags:** Key-value metadata pairs describing map features

**LRU Cache:** Least Recently Used cache eviction strategy

**MVVM:** Model-View-ViewModel architectural pattern

**SwiftUI:** Apple's modern declarative UI framework

**MapKit:** Apple's mapping framework

**SF Symbols:** Apple's system icon library

**UserDefaults:** iOS key-value persistence for app preferences

**Scene Phase:** SwiftUI app lifecycle state (active, inactive, background)

**Bottom Sheet:** Draggable sheet UI component (iPhone)

**Split View:** Side-by-side layout (iPad)

**Detent:** Sheet height position (small, medium, large)

**Geocoding:** Converting coordinates to human-readable addresses

**Annotation:** Map marker representing a location

**Clustering:** Grouping nearby map markers into a single marker

---

## Appendix C: Contact & Support

**Developer:** Brink 13 Labs (Joe Castagnaro)

**Support Email:** support@bitlocal.app

**Website:** https://bitlocal.app

**Company Website:** https://brink13labs.com

**Social Media:**
- X/Twitter: @bitlocal_app

**Privacy Policy:** https://github.com/joeycast/BitLocal.app/blob/main/Privacy_Policy.md

**Bug Reports:** support@bitlocal.app

**Feature Requests:** support@bitlocal.app

**General Inquiries:** support@bitlocal.app

---

## Document Changelog

**Version 2.0.5 (December 29, 2025):**
- Initial comprehensive specification document
- Covers all features in build 43
- Documents complete architecture and design decisions

---

**End of Specification**

This document comprehensively defines BitLocal as of version 2.0.5 (build 43). For the most up-to-date information, refer to the source code repository and official documentation.
