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
        // Backup inventory, integrity hashing, and rebuild planning; Foundation-only so that it tests on Linux.
        .target(name: "RebuildCore"),
        // macOS-only file operations; the sources are empty on other platforms.
        .target(name: "LibraryMac"),
        .target(name: "ConversionMac"),
        .executableTarget(
            name: "ilibrary",
            dependencies: [
                "MP4Core", "FLACCore", "CatalogCore",
                .target(name: "LibraryMac", condition: .when(platforms: [.macOS])),
                .target(name: "ConversionMac", condition: .when(platforms: [.macOS])),
            ]),
        // Validates private reference files under reference-private/; not part of the public suite.
        .executableTarget(name: "ReferenceProbe", dependencies: ["MP4Core", "FLACCore"]),
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
                "ilibrary", "MP4Core", "FLACCore", "CatalogCore", "SyntheticMedia",
                .target(name: "SyntheticMediaMac", condition: .when(platforms: [.macOS])),
                .target(name: "ConversionMac", condition: .when(platforms: [.macOS])),
            ]),
    ]
)
