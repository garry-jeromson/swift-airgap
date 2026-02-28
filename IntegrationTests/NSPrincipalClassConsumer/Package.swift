// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NSPrincipalClassConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .testTarget(
            name: "NSPrincipalClassConsumerTests",
            dependencies: [
                .product(name: "Airgap", package: "swift-airgap")
            ]
        )
    ]
)
