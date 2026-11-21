// swift-tools-version:5.3
import PackageDescription
let package = Package(name: "InboxCore", products: [.library(name: "InboxCore", targets: ["InboxCore"])], targets: [
    .target(name: "InboxCore"), .testTarget(name: "InboxCoreTests", dependencies: ["InboxCore"])
])
