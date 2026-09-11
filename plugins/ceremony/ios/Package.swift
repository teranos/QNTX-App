// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "tauri-plugin-ceremony",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "tauri-plugin-ceremony",
            type: .static,
            targets: ["tauri-plugin-ceremony"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "tauri-plugin-ceremony",
            dependencies: [
                .byName(name: "Tauri")
            ],
            path: "Sources")
    ]
)
