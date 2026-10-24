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
        .library(name: "StyleToneUI", targets: ["StyleToneUI"])
    ],
    targets: [
        .target(
            name: "StyleToneCore",
            path: "Packages/StyleToneCore/Sources/StyleToneCore"
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
        .testTarget(
            name: "StyleToneCoreTests",
            dependencies: ["StyleToneCore"],
            path: "Packages/StyleToneCore/Tests/StyleToneCoreTests"
        ),
        .testTarget(
            name: "StyleToneImagingTests",
            dependencies: ["StyleToneImaging"],
            path: "Packages/StyleToneImaging/Tests/StyleToneImagingTests"
        ),
        .testTarget(
            name: "StyleToneVisionTests",
            dependencies: ["StyleToneVision"],
            path: "Packages/StyleToneVision/Tests/StyleToneVisionTests"
        ),
        .testTarget(
            name: "StyleToneGeometryTests",
            dependencies: ["StyleToneGeometry"],
            path: "Packages/StyleToneGeometry/Tests/StyleToneGeometryTests"
        ),
        .testTarget(
            name: "StyleToneRetouchTests",
            dependencies: ["StyleToneRetouch"],
            path: "Packages/StyleToneRetouch/Tests/StyleToneRetouchTests"
        ),
        .testTarget(
            name: "StyleToneLearningTests",
            dependencies: ["StyleToneLearning"],
            path: "Packages/StyleToneLearning/Tests/StyleToneLearningTests"
        ),
        .testTarget(
            name: "StyleTonePersistenceTests",
            dependencies: ["StyleTonePersistence"],
            path: "Packages/StyleTonePersistence/Tests/StyleTonePersistenceTests"
        ),
        .testTarget(
            name: "StyleToneCommerceTests",
            dependencies: ["StyleToneCommerce"],
            path: "Packages/StyleToneCommerce/Tests/StyleToneCommerceTests"
        ),
        .testTarget(
            name: "StyleToneUITests",
            dependencies: ["StyleToneUI"],
            path: "Packages/StyleToneUI/Tests/StyleToneUITests"
        )
    ],
    swiftLanguageModes: [.v6]
)
