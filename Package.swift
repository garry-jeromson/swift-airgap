// swift-tools-version: 6.0

import Foundation
import PackageDescription

let enableSwiftLint = ProcessInfo.processInfo.environment["ENABLE_SWIFTLINT"] != nil

let swiftLintDependencies: [Package.Dependency] = enableSwiftLint
    ? [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.2"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.6"),
    ]
    : []

let package = Package(
    name: "Airgap",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "Airgap", targets: ["Airgap"]),
    ],
    dependencies: swiftLintDependencies,
    targets: [
        .target(
            name: "Airgap"),
        .testTarget(
            name: "AirgapXCTestIntegrationTests",
            dependencies: ["Airgap"]),
        .testTarget(
            name: "AirgapUnitTests",
            dependencies: ["Airgap"]),
        .testTarget(
            name: "AirgapSwiftTestingIntegrationTests",
            dependencies: ["Airgap"]),
    ])
