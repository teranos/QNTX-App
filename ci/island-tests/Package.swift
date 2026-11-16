// swift-tools-version:5.9
// The island's own Swift, compiled and tested in the iPhone Simulator: the
// same files the app and its widget compile (island/shared, island/app),
// linked here, with the same Sentry and SacredError the build pins
// (.github/scripts/ios-project.py).
//
//   xcodebuild test -scheme IslandTests -destination 'platform=iOS Simulator,name=<an iPhone>'
import PackageDescription

let package = Package(
    name: "IslandTests",
    platforms: [.iOS("17.2")],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.32.0"),
        .package(url: "https://github.com/teranos/sacred-error", revision: "7afcdfd0c060669ad7032f07467f61761a7fac39"),
    ],
    targets: [
        .target(
            name: "Island",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "SacredError", package: "sacred-error"),
            ],
            path: "Sources",
            // Objective-C, which a Swift target does not hold: it only begins the hand-over at launch.
            exclude: ["app/WaitsBoot.m"]
        ),
        .testTarget(
            name: "IslandTests",
            dependencies: [
                "Island",
                .product(name: "SacredError", package: "sacred-error"),
            ],
            path: "Tests/IslandTests"
        ),
    ]
)
