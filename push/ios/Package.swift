// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "push",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "push",
            type: .static,
            targets: ["push"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api")
    ],
    targets: [
        .target(
            name: "push",
            dependencies: [
                .byName(name: "Tauri")
            ],
            path: "Sources")
    ]
)
