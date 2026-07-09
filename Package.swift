// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marea",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Marea",
            path: "Sources/Marea",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
