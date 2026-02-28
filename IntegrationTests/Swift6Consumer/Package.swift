// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Swift6Consumer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Swift6Consumer",
            dependencies: [
                .product(name: "Airgap", package: "swift-airgap")
            ]
        )
    ]
)
