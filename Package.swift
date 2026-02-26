// swift-tools-version: 6.0

import Foundation
import PackageDescription

let swiftLintPlugins: [Target.PluginUsage]
if ProcessInfo.processInfo.environment["DISABLE_SWIFTLINT"] == nil {
    swiftLintPlugins = [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
} else {
    swiftLintPlugins = []
}

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
            plugins: swiftLintPlugins
        ),
        .testTarget(
            name: "AirgapXCTestIntegrationTests",
            dependencies: ["Airgap"],
            plugins: swiftLintPlugins
        ),
        .testTarget(
            name: "AirgapUnitTests",
            dependencies: ["Airgap"],
            plugins: swiftLintPlugins
        ),
        .testTarget(
            name: "AirgapSwiftTestingIntegrationTests",
            dependencies: ["Airgap"],
            plugins: swiftLintPlugins
        ),
    ]
)
