// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CloudBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CloudBridge", targets: ["CloudBridge"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CloudBridge",
            dependencies: []
        )
    ]
)
