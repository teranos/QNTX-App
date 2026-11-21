// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "chat",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "chat",
            type: .static,
            targets: ["chat"]),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api"),
        .package(url: "https://github.com/exyte/Chat.git", exact: "3.3.7"),
    ],
    targets: [
        .target(
            name: "chat",
            dependencies: [
                .byName(name: "Tauri"),
                .product(name: "ExyteChat", package: "Chat"),
            ],
            path: "Sources")
    ]
)
