// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "chess-puzzles-menuitem",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "chess-puzzles-menuitem",
            targets: ["App"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/awxkee/zstd.swift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [.product(name: "zstd", package: "zstd.swift")]
        )
    ]
)

