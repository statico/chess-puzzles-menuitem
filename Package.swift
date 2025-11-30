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
    targets: [
        .executableTarget(
            name: "App"
        )
    ]
)

