// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Airgap",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Airgap", targets: ["Airgap"]),
    ],
    targets: [
        .target(name: "Airgap", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AirgapTests", dependencies: ["Airgap"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AirgapXCTestIntegrationTests", dependencies: ["Airgap"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AirgapSwiftTestingTests", dependencies: ["Airgap"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
