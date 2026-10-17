// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MagicWallCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MagicWallCore", targets: ["MagicWallCore"]),
        .executable(name: "mwctl", targets: ["mwctl"])
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
        ),
        .executableTarget(
            name: "mwctl",
            dependencies: ["MagicWallCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
