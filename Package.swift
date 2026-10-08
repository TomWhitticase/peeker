// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Peeker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Peeker", path: "Sources/Peeker")
    ]
)
