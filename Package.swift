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
        .executableTarget(name: "ilibrary"),
        .testTarget(name: "MP4CoreTests", dependencies: ["MP4Core"]),
        .testTarget(name: "FLACCoreTests", dependencies: ["FLACCore"]),
    ]
)
