// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "sheet",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "sheet",
            type: .static,
            targets: ["sheet"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "sheet",
            dependencies: [
                .byName(name: "Tauri")
            ],
            path: "Sources")
    ]
)
