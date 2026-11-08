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
            targets: ["BitLocalDomain", "BitLocalDesign"]
        ),
    ],
    targets: [
        .target(name: "BitLocalDomain"),
        .target(name: "BitLocalDesign"),
        .testTarget(
            name: "BitLocalDomainTests",
            dependencies: ["BitLocalDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
