// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "power",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "power",
            type: .static,
            targets: ["power"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "power",
            dependencies: [
                .byName(name: "Tauri")
            ],
            path: "Sources")
    ]
)
