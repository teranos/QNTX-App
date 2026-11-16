// swift-tools-version:5.9
// The island's wall: what of island/ drops a failure, read from its syntax.
// Run from ci/island-wall: swift run island-wall ../../island
import PackageDescription

let package = Package(
    name: "IslandWall",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", exact: "604.0.0")
    ],
    targets: [
        .executableTarget(
            name: "island-wall",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/IslandWall"
        )
    ]
)
