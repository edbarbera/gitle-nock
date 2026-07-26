// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitleNock",
    // Liquid Glass (`glassEffect`, `GlassEffectContainer`) is macOS 26 and up.
    // Stated as a string because tools-version 5.9 predates the `.v26` case.
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "GitleNock",
            path: "Sources/GitleNock"
        )
    ]
)
