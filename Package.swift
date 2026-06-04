// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacCleanerApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "MacCleanerApp",
            dependencies: [
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
