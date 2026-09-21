// swift-tools-version: 6.0
// Odomind — portable domain core.
//
// This package deliberately contains no UIKit, SwiftUI, SwiftData or EventKit
// code so that the scheduling engine, catalog decoding and transfer formats can
// be compiled and tested on any platform that ships Foundation, including the
// Linux hosts used for quick pre-flight checks. The iOS app links this package
// and supplies the platform-specific layers.

import PackageDescription

let package = Package(
    name: "OdomindCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "OdomindCore", targets: ["OdomindCore"]),
        .executable(name: "odomind-catalog", targets: ["OdomindCatalogTool"])
    ],
    targets: [
        .target(
            name: "OdomindCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "OdomindCatalogTool",
            dependencies: ["OdomindCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OdomindCoreTests",
            dependencies: ["OdomindCore"],
            // Carries the Build 1 backup fixture. Reading a real file rather
            // than a string literal is deliberate: the fixture is the shape
            // that shipped, and it should be awkward to quietly edit.
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
