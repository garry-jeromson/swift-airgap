// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Airgap",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "Airgap", targets: ["Airgap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.2"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.6"),
    ],
    targets: [
        .target(
            name: "Airgap",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "AirgapTests",
            dependencies: ["Airgap"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "AirgapXCTestIntegrationTests",
            dependencies: ["Airgap"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "AirgapSwiftTestingTests",
            dependencies: ["Airgap"],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
    ]
)
