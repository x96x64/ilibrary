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
        // macOS-only file operations; the sources are empty on other platforms.
        .target(name: "LibraryMac"),
        .executableTarget(
            name: "ilibrary",
            dependencies: [
                "MP4Core", "CatalogCore", .target(name: "LibraryMac", condition: .when(platforms: [.macOS])),
            ]),
        // Validates private reference files under reference-private/; not part of the public suite.
        .executableTarget(name: "ReferenceProbe", dependencies: ["MP4Core", "FLACCore"]),
        // Synthetic media shared by the test targets.
        .target(name: "SyntheticMedia", path: "Tests/SyntheticMedia"),
        .testTarget(name: "MP4CoreTests", dependencies: ["MP4Core", "SyntheticMedia"]),
        .testTarget(name: "FLACCoreTests", dependencies: ["FLACCore"]),
        .testTarget(name: "CatalogCoreTests", dependencies: ["CatalogCore"]),
        .testTarget(name: "LibraryMacTests", dependencies: ["LibraryMac"]),
    ]
)
