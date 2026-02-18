// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpeakSel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpeakSel",
            path: "Sources"
        )
    ]
)
