// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "shake",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "shake",
            type: .static,
            targets: ["shake"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "shake",
            dependencies: [
                .byName(name: "Tauri")
            ],
            path: "Sources")
    ]
)
