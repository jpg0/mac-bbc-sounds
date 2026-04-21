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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BBCSoundsMenuBar",
            dependencies: [],
            path: "Sources/BBCSoundsMenuBar"
        )
    ]
)
