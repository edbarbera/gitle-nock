// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitleNock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GitleNock",
            path: "Sources/GitleNock"
        )
    ]
)
