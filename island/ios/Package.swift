// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "island",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "island",
            type: .static,
            targets: ["island"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "island",
            dependencies: [
                .byName(name: "Tauri")
            ],
            path: "Sources")
    ]
)
