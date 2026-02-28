// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XCTestConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .testTarget(
            name: "XCTestConsumerTests",
            dependencies: [
                .product(name: "Airgap", package: "swift-airgap")
            ]
        )
    ]
)
