// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kado",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kado",
            path: "Sources/Kado",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
