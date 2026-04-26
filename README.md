# BitLocal

Find places that accept Bitcoin.

BitLocal is a native iOS app for discovering real-world businesses where you can spend bitcoin. It puts Bitcoin-friendly merchants on an interactive map, shows accepted payment methods like on-chain, Lightning, and contactless Lightning, and helps people support the circular Bitcoin economy without accounts, ads, or tracking.

Whether you are looking for coffee, food, travel stops, shops, events, or nearby Bitcoin communities, BitLocal is built to make the physical Bitcoin economy easier to find.

## Highlights

- Interactive map of Bitcoin-accepting businesses
- Merchant details with address, website, phone, opening hours, and payment method data when available
- Search and category discovery for nearby places
- Directions through Apple Maps
- Optional location access, with the app still usable if location is denied
- Optional merchant alerts for cities you care about
- BTC Map and OpenStreetMap attribution
- Privacy-forward design with no BitLocal account, ads, analytics SDKs, or third-party tracking
- Universal iPhone and iPad support

## Why BitLocal Exists

Bitcoin is most useful when people can use it in everyday life. BitLocal helps close the gap between people who hold bitcoin and the local businesses willing to accept it.

The goal is simple: make it easier to find, visit, and support Bitcoin-friendly places in the real world.

## Screenshots

Screenshots coming soon.

Recommended GitHub/App Store coverage:

- Map view with nearby merchants
- Search and filtering
- Merchant detail screen
- Payment method display
- iPad layout

## Built With

BitLocal is built as a modern, native iOS app:

- Swift and SwiftUI
- MapKit and CoreLocation
- CloudKit and Apple Push Notifications for optional merchant alerts
- BTC Map public APIs
- OpenStreetMap merchant/location data
- Xcode project based workflow
- No external runtime dependencies

The app currently targets iOS 18 or later.

## Getting Started

### Requirements

- macOS with Xcode installed
- iOS 18+ simulator or device
- Apple developer setup if you want to run CloudKit, push notifications, or distribution workflows

### Clone

```bash
git clone git@github.com:joeycast/BitLocal.git
cd BitLocal
```

### Open in Xcode

```bash
open bitlocal.xcodeproj
```

Select the `bitlocal` scheme, choose an iOS simulator, and run.

### Build from the command line

```bash
xcodebuild \
  -project bitlocal.xcodeproj \
  -scheme bitlocal \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Run tests

```bash
xcodebuild test \
  -project bitlocal.xcodeproj \
  -scheme bitlocal \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project Structure

```text
BitLocal/
+-- Businesses/          # Merchant models, views, and business detail flows
+-- Map/                 # MapKit views, annotations, and map state
+-- Onboarding/          # First-launch experience
+-- Settings/            # Preferences, resources, and support surfaces
+-- Shared/              # Shared SwiftUI views, helpers, networking, and app state
+-- bitlocalTests/       # Unit tests
+-- docs/                # Project docs and operational notes
+-- scripts/             # Supporting automation scripts
`-- bitlocal.xcodeproj   # Xcode project
```

## Data and Privacy

BitLocal displays public merchant data from BTC Map and OpenStreetMap. Location permission is optional and used for app functionality like centering the map and calculating nearby results.

BitLocal does not require user accounts, does not sell personal information, and does not include advertising or analytics SDKs. See [Privacy_Policy.md](Privacy_Policy.md) for details.

## Merchant Alerts

BitLocal includes optional city-based merchant alerts. When enabled, the app can notify users when new Bitcoin-friendly places appear in a selected city.

The supporting CloudKit pipeline is documented in [docs/cloudkit-merchant-alerts.md](docs/cloudkit-merchant-alerts.md).

## Contributing

Contributions are welcome, especially around:

- Improving merchant discovery and search
- Polishing the iOS experience
- Fixing bugs and edge cases
- Expanding tests
- Improving documentation
- Making Bitcoin merchant data easier to understand

Before opening a pull request:

1. Build the app locally.
2. Run the test suite.
3. Keep changes focused and easy to review.
4. Include screenshots or screen recordings for visible UI changes.

## License

BitLocal is released under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE).

## Links

- Website: [bitlocal.app](https://bitlocal.app)
- Privacy: [bitlocal.app/privacy](https://www.bitlocal.app/privacy)
- Data: [BTC Map](https://btcmap.org)
- Maps: [OpenStreetMap](https://www.openstreetmap.org)
- Support: [support@bitlocal.app](mailto:support@bitlocal.app)
