// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RightDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RightDock",
            path: "Sources/RightDock"
        ),
    ]
)
