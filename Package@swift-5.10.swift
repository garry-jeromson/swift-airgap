// swift-tools-version: 5.10

// Swift 5.10–specific manifest: excludes Swift Testing test targets that require Swift 6.0+.
// SwiftPM uses this manifest when the toolchain is Swift 5.10.x, and Package.swift otherwise.

import Foundation
import PackageDescription

let enableSwiftLint = ProcessInfo.processInfo.environment["ENABLE_SWIFTLINT"] != nil

let swiftLintPlugins: [Target.PluginUsage] = enableSwiftLint
    ? [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
    : []

let swiftLintDependencies: [Package.Dependency] = enableSwiftLint
    ? [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.2"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.6"),
    ]
    : []

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "Airgap",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "Airgap", targets: ["Airgap"]),
    ],
    dependencies: swiftLintDependencies,
    targets: [
        .target(
            name: "Airgap",
            swiftSettings: strictConcurrency,
            plugins: swiftLintPlugins
        ),
        .testTarget(
            name: "AirgapXCTestIntegrationTests",
            dependencies: ["Airgap"],
            swiftSettings: strictConcurrency,
            plugins: swiftLintPlugins
        ),
    ]
)
