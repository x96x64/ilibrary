// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iLibrary",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ilibrary", targets: ["ilibrary"])],
    targets: [
        // Foundation-only targets build and test on Linux.
        .target(name: "MP4Core"),
        .target(name: "FLACCore"),
        .target(name: "CatalogCore"),
        // Backup inventory, integrity hashing, and rebuild planning.
        .target(name: "RebuildCore"),
        // macOS-only file operations; the sources are empty on other platforms.
        .target(name: "LibraryMac", dependencies: ["RebuildCore"]),
        .target(name: "ConversionMac"),
        .executableTarget(
            name: "ilibrary",
            dependencies: [
                "MP4Core", "FLACCore", "CatalogCore", "RebuildCore",
                .target(name: "LibraryMac", condition: .when(platforms: [.macOS])),
                .target(name: "ConversionMac", condition: .when(platforms: [.macOS])),
            ]),
        // Synthetic media shared by the test targets.
        .target(name: "SyntheticMedia", path: "Tests/SyntheticMedia"),
        .target(name: "SyntheticMediaMac", path: "Tests/SyntheticMediaMac"),
        .testTarget(name: "MP4CoreTests", dependencies: ["MP4Core", "SyntheticMedia"]),
        .testTarget(name: "FLACCoreTests", dependencies: ["FLACCore"]),
        .testTarget(name: "CatalogCoreTests", dependencies: ["CatalogCore"]),
        .testTarget(name: "RebuildCoreTests", dependencies: ["RebuildCore"]),
        .testTarget(name: "LibraryMacTests", dependencies: ["LibraryMac"]),
        .testTarget(
            name: "ConversionMacTests", dependencies: ["ConversionMac", "SyntheticMedia", "SyntheticMediaMac"]),
        .testTarget(
            name: "ilibraryTests",
            dependencies: [
                "ilibrary", "MP4Core", "FLACCore", "CatalogCore", "RebuildCore", "SyntheticMedia",
                .target(name: "SyntheticMediaMac", condition: .when(platforms: [.macOS])),
                .target(name: "ConversionMac", condition: .when(platforms: [.macOS])),
                .target(name: "LibraryMac", condition: .when(platforms: [.macOS])),
            ]),
    ]
)
