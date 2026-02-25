// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Airgap",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Airgap", targets: ["Airgap"]),
    ],
    targets: [
        .target(name: "Airgap"),
        .testTarget(name: "AirgapTests", dependencies: ["Airgap"]),
        .testTarget(name: "AirgapXCTestIntegrationTests", dependencies: ["Airgap"]),
        .testTarget(name: "AirgapSwiftTestingTests", dependencies: ["Airgap"]),
    ]
)
