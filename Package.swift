// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BBCSoundsMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BBCSoundsMenuBar", targets: ["BBCSoundsMenuBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/pierrickrouxel/SSDPClient.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "BBCSoundsMenuBar",
            dependencies: [
                .product(name: "SSDPClient", package: "SSDPClient")
            ],
            path: "Sources/BBCSoundsMenuBar"
        ),
        .testTarget(
            name: "BBCSoundsMenuBarTests",
            dependencies: ["BBCSoundsMenuBar"],
            path: "Tests/BBCSoundsMenuBarTests"
        )
    ]
)
