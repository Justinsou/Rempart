// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rempart",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rempart",
            path: "Sources/Rempart"
        )
    ]
)
