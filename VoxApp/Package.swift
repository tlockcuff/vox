// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Vox",
            path: "Sources"
        )
    ]
)
