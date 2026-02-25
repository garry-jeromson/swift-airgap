// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetworkGuard",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "NetworkGuard", targets: ["NetworkGuard"]),
    ],
    targets: [
        .target(name: "NetworkGuard", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "NetworkGuardTests", dependencies: ["NetworkGuard"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "NetworkGuardXCTestIntegrationTests", dependencies: ["NetworkGuard"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "NetworkGuardSwiftTestingTests", dependencies: ["NetworkGuard"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
