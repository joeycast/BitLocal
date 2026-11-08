// swift-tools-version: 6.0
// BitLocalKit: the redesign's domain, data and design-system code.
// Zero third-party dependencies (see docs/redesign/architecture-redesign.md section 10).

import PackageDescription

let package = Package(
    name: "BitLocalKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "BitLocalKit",
            targets: ["BitLocalDomain", "BitLocalData", "BitLocalNavigation", "BitLocalDesign"]
        ),
    ],
    targets: [
        .target(name: "BitLocalDomain"),
        .target(
            name: "BitLocalData",
            dependencies: ["BitLocalDomain"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "BitLocalNavigation", dependencies: ["BitLocalDomain"]),
        .target(name: "BitLocalDesign"),
        .testTarget(
            name: "BitLocalDomainTests",
            dependencies: ["BitLocalDomain"]
        ),
        .testTarget(
            name: "BitLocalDataTests",
            dependencies: ["BitLocalData", "BitLocalDomain"]
        ),
        .testTarget(
            name: "BitLocalNavigationTests",
            dependencies: ["BitLocalNavigation", "BitLocalDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
