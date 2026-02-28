// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftTestingConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .testTarget(
            name: "SwiftTestingConsumerTests",
            dependencies: [
                .product(name: "Airgap", package: "swift-airgap")
            ]
        )
    ]
)
