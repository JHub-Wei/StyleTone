// swift-tools-version: 6.0
//
// Standalone package for the platform-neutral WP-24 performance harness.
//
// The root package also builds these sources as the `PerformanceKit` target
// (see docs/performance/integration/Package.swift.patch). Keeping a nested
// manifest lets the gate/thermal/memory logic be type-checked and tested in
// isolation, including on a host without the iOS SDK.
import PackageDescription

let package = Package(
    name: "PerformanceKit",
    products: [
        .library(name: "PerformanceKit", targets: ["PerformanceKit"])
    ],
    targets: [
        .target(
            name: "PerformanceKit",
            path: "Sources/PerformanceKit"
        ),
        .testTarget(
            name: "PerformanceKitTests",
            dependencies: ["PerformanceKit"],
            path: "Tests/PerformanceKitTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
