// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MagicWallCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MagicWallCore", targets: ["MagicWallCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "MagicWallCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MagicWallCoreTests",
            dependencies: ["MagicWallCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
