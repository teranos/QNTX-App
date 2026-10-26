// swift-tools-version:5.3
import PackageDescription
let package = Package(name: "share", platforms: [.iOS(.v14)], products: [
    .library(name: "share", type: .static, targets: ["share"])
], dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api"),
    .package(name: "InboxCore", path: "InboxCore")
], targets: [.target(name: "share", dependencies: [.byName(name: "Tauri"), .byName(name: "InboxCore")], path: "Sources")])
