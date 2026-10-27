// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StyleTone",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "StyleToneCore", targets: ["StyleToneCore"]),
        .library(name: "StyleToneImaging", targets: ["StyleToneImaging"]),
        .library(name: "StyleToneVision", targets: ["StyleToneVision"]),
        .library(name: "StyleToneGeometry", targets: ["StyleToneGeometry"]),
        .library(name: "StyleToneRetouch", targets: ["StyleToneRetouch"]),
        .library(name: "StyleToneLearning", targets: ["StyleToneLearning"]),
        .library(name: "StyleTonePersistence", targets: ["StyleTonePersistence"]),
        .library(name: "StyleToneCommerce", targets: ["StyleToneCommerce"]),
        .library(name: "StyleToneUI", targets: ["StyleToneUI"]),
        // WP-04 test infrastructure. Library products let XcodeGen/App test
        // targets link them later; SwiftPM test targets use the targets directly.
        .library(name: "GoldenSupport", targets: ["GoldenSupport"]),
        .library(name: "TestShared", targets: ["TestShared"])
    ],
    targets: [
        .target(
            name: "StyleToneCore",
            path: "Packages/StyleToneCore/Sources/StyleToneCore"
        ),
        .target(
            name: "GoldenSupport",
            dependencies: ["StyleToneCore"],
            path: "Tests/GoldenSupport/Sources/GoldenSupport"
        ),
        .target(
            name: "TestShared",
            dependencies: ["StyleToneCore", "GoldenSupport"],
            path: "Tests/Shared/Sources/TestShared"
        ),
        // WP-24 performance harness. The target is platform-neutral; the
        // integration test target below owns the device/CI scenarios.
        .target(
            name: "PerformanceKit",
            path: "Tests/Performance/Harness/Sources/PerformanceKit"
        ),
        .target(
            name: "StyleToneImaging",
            dependencies: ["StyleToneCore"],
            path: "Packages/StyleToneImaging/Sources/StyleToneImaging"
        ),
        .target(
            name: "StyleToneVision",
            dependencies: ["StyleToneCore", "StyleToneImaging"],
            path: "Packages/StyleToneVision/Sources/StyleToneVision"
        ),
        .target(
            name: "StyleToneGeometry",
            dependencies: ["StyleToneCore", "StyleToneImaging"],
            path: "Packages/StyleToneGeometry/Sources/StyleToneGeometry"
        ),
        .target(
            name: "StyleToneRetouch",
            dependencies: ["StyleToneCore", "StyleToneImaging"],
            path: "Packages/StyleToneRetouch/Sources/StyleToneRetouch"
        ),
        .target(
            name: "StyleToneLearning",
            dependencies: ["StyleToneCore"],
            path: "Packages/StyleToneLearning/Sources/StyleToneLearning"
        ),
        .target(
            name: "StyleTonePersistence",
            dependencies: ["StyleToneCore"],
            path: "Packages/StyleTonePersistence/Sources/StyleTonePersistence"
        ),
        .target(
            name: "StyleToneCommerce",
            dependencies: ["StyleToneCore"],
            path: "Packages/StyleToneCommerce/Sources/StyleToneCommerce"
        ),
        .target(
            name: "StyleToneUI",
            dependencies: ["StyleToneCore", "StyleToneImaging"],
            path: "Packages/StyleToneUI/Sources/StyleToneUI"
        ),
        // Every module test target can `import GoldenSupport` for image
        // comparison and `import TestShared` for the shared mocks.
        .testTarget(
            name: "StyleToneCoreTests",
            dependencies: ["StyleToneCore", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneCore/Tests/StyleToneCoreTests"
        ),
        .testTarget(
            name: "StyleToneImagingTests",
            dependencies: ["StyleToneImaging", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneImaging/Tests/StyleToneImagingTests"
        ),
        .testTarget(
            name: "StyleToneVisionTests",
            dependencies: ["StyleToneVision", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneVision/Tests/StyleToneVisionTests"
        ),
        .testTarget(
            name: "StyleToneGeometryTests",
            dependencies: ["StyleToneGeometry", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneGeometry/Tests/StyleToneGeometryTests"
        ),
        .testTarget(
            name: "StyleToneRetouchTests",
            dependencies: ["StyleToneRetouch", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneRetouch/Tests/StyleToneRetouchTests"
        ),
        .testTarget(
            name: "StyleToneLearningTests",
            dependencies: ["StyleToneLearning", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneLearning/Tests/StyleToneLearningTests"
        ),
        .testTarget(
            name: "StyleTonePersistenceTests",
            dependencies: ["StyleTonePersistence", "GoldenSupport", "TestShared"],
            path: "Packages/StyleTonePersistence/Tests/StyleTonePersistenceTests"
        ),
        .testTarget(
            name: "StyleToneCommerceTests",
            dependencies: ["StyleToneCommerce", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneCommerce/Tests/StyleToneCommerceTests"
        ),
        .testTarget(
            name: "StyleToneUITests",
            dependencies: ["StyleToneUI", "GoldenSupport", "TestShared"],
            path: "Packages/StyleToneUI/Tests/StyleToneUITests"
        ),
        .testTarget(
            name: "GoldenSupportTests",
            dependencies: ["GoldenSupport", "TestShared", "StyleToneCore"],
            path: "Tests/GoldenSupport/Tests/GoldenSupportTests"
        ),
        .testTarget(
            name: "TestSharedTests",
            dependencies: ["TestShared", "StyleToneCore"],
            path: "Tests/Shared/Tests/TestSharedTests"
        ),
        .testTarget(
            name: "StyleTonePerformanceTests",
            dependencies: [
                "PerformanceKit",
                "StyleToneCore",
                "StyleToneImaging",
                "StyleToneGeometry",
                "StyleToneLearning",
                "StyleToneUI",
                "GoldenSupport",
                "TestShared"
            ],
            path: "Tests/Performance/Tests/PerformanceTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
